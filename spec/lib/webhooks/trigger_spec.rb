require 'rails_helper'

describe Webhooks::Trigger do
  include ActiveJob::TestHelper

  subject(:trigger) { described_class }

  let!(:account) { create(:account) }
  # O fork valida `pending_status_allowed_by_inbox` (conversation.rb:461, commit
  # da2ea07ed1). Sem a flag, todo `create(:conversation, status: :pending)` deste
  # arquivo levanta RecordInvalid — eram 6 vermelhos herdados do upstream.
  let!(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }
  let!(:conversation) { create(:conversation, inbox: inbox) }
  let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }

  let(:webhook_type) { :api_inbox_webhook }
  let(:url) { 'https://test.com' }
  let(:payload) { { hello: :hello } }
  let(:fetch_result) { instance_double(SafeFetch::Result) }
  let(:agent_bot_error_content) { I18n.t('conversations.activity.agent_bot.error_moved_to_open') }
  let(:default_timeout) { 5 }
  let(:webhook_timeout) { default_timeout }
  let(:base_headers) { { 'Content-Type' => 'application/json', 'Accept' => 'application/json' } }

  before do
    ActiveJob::Base.queue_adapter = :test
    allow(GlobalConfig).to receive(:get_value).and_call_original
    allow(GlobalConfig).to receive(:get_value).with('WEBHOOK_TIMEOUT').and_return(webhook_timeout)
    allow(GlobalConfig).to receive(:get_value).with('DEPLOYMENT_ENV').and_return(nil)
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe '#execute' do
    it 'triggers webhook' do
      expect(SafeFetch).to receive(:fetch).with(
        url,
        method: :post,
        body: payload.to_json,
        headers: base_headers,
        open_timeout: webhook_timeout,
        read_timeout: webhook_timeout,
        validate_content_type: false
      ).and_yield(fetch_result)

      trigger.execute(url, payload, webhook_type)
    end

    # B3: um 500 e transitorio. Antes, `execute` engolia o erro e ja marcava a
    # mensagem como falha — o job terminava com sucesso e nao havia reentrega.
    # Agora a excecao sobe e quem marca a falha e `handle_failure`, chamado uma
    # unica vez pelo WebhookJob quando as 5 tentativas se esgotam.
    # (o caso message_created equivalente esta em 'lets a 500 rise for non-agent
    # webhooks so the job can retry', mais abaixo — e o exemplo do upstream que
    # afirmava o defeito, renomeado no lugar.)
    it 'raises on a 500 for message-updated instead of silently marking the message failed' do
      payload = { event: 'message_updated', conversation: { id: conversation.id }, id: message.id }

      expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))

      expect { trigger.execute(url, payload, webhook_type) }
        .to raise_error(SafeFetch::HttpError, '500 Internal Server Error')
      expect(message.reload.status).to eq('sent')
    end

    it 'marks the message failed when handle_failure is called for message-created' do
      payload = { event: 'message_created', conversation: { id: conversation.id }, id: message.id }
      error = SafeFetch::HttpError.new('500 Internal Server Error')

      expect { trigger.new(url, payload, webhook_type).handle_failure(error) }
        .to change { message.reload.status }.from('sent').to('failed')
    end

    it 'does not retry a 404 — the destination refused the payload' do
      payload = { event: 'message_created', conversation: { id: conversation.id }, id: message.id }

      expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found'))

      expect { trigger.execute(url, payload, webhook_type) }.not_to raise_error
      expect(message.reload.status).to eq('failed')
    end

    it 'retries a 429 — the destination asked us to back off' do
      payload = { event: 'message_created', conversation: { id: conversation.id }, id: message.id }

      expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('429 Too Many Requests'))

      expect { trigger.execute(url, payload, webhook_type) }
        .to raise_error(SafeFetch::HttpError, '429 Too Many Requests')
      expect(message.reload.status).to eq('sent')
    end

    it 'retries a read timeout' do
      payload = { event: 'message_created', conversation: { id: conversation.id }, id: message.id }

      expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('Net::ReadTimeout'))

      expect { trigger.execute(url, payload, webhook_type) }.to raise_error(SafeFetch::FetchError)
      expect(message.reload.status).to eq('sent')
    end

    # Um corpo grande so e recusado DEPOIS de um 2xx (safe_fetch/fetcher.rb:35
    # ignora o corpo de quem nao e Net::HTTPSuccess). A entrega ja aconteceu —
    # reentregar duplicaria o webhook no destino.
    it 'does not retry an oversized response body, because delivery already happened' do
      payload = { event: 'message_created', conversation: { id: conversation.id }, id: message.id }

      expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FileTooLargeError.new('exceeded 42 bytes'))

      expect { trigger.execute(url, payload, webhook_type) }.not_to raise_error
      expect(message.reload.status).to eq('failed')
    end

    it 'treats blocked private webhook URLs as failures' do
      payload = { event: 'message_created', conversation: { id: conversation.id }, id: message.id }

      expect { trigger.execute('http://127.0.0.1/webhook', payload, webhook_type) }
        .to change { message.reload.status }.from('sent').to('failed')
    end

    context 'when webhook type is agent bot' do
      let(:webhook_type) { :agent_bot_webhook }
      let!(:pending_conversation) { create(:conversation, inbox: inbox, status: :pending, account: account) }
      let!(:pending_message) { create(:message, account: account, inbox: inbox, conversation: pending_conversation) }

      it 'raises 500 errors for retry and does not reopen conversation immediately' do
        payload = { event: 'message_created', id: pending_message.id }

        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))

        expect { trigger.execute(url, payload, webhook_type) }
          .to(raise_error do |error|
            expect(error.class.name).to eq('Webhooks::Trigger::RetryableError')
            expect(error.status).to eq(500)
          end)
        expect(pending_conversation.reload.status).to eq('pending')
        expect(Conversations::ActivityMessageJob).not_to have_been_enqueued
      end

      it 'raises 429 errors for retry and does not reopen conversation immediately' do
        payload = { event: 'message_created', id: pending_message.id }

        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('429 Too Many Requests'))

        expect { trigger.execute(url, payload, webhook_type) }
          .to(raise_error do |error|
            expect(error.class.name).to eq('Webhooks::Trigger::RetryableError')
            expect(error.status).to eq(429)
          end)
        expect(pending_conversation.reload.status).to eq('pending')
        expect(Conversations::ActivityMessageJob).not_to have_been_enqueued
      end

      it 'reopens conversation and enqueues activity message if pending' do
        payload = { event: 'message_created', id: pending_message.id }

        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found'))

        expect do
          perform_enqueued_jobs do
            trigger.execute(url, payload, webhook_type)
          end
        end.not_to(change { pending_message.reload.status })

        expect(pending_conversation.reload.status).to eq('open')

        activity_message = pending_conversation.reload.messages.order(:created_at).last
        expect(activity_message.message_type).to eq('activity')
        expect(activity_message.content).to eq(agent_bot_error_content)
      end

      it 'does not change message status or enqueue activity when conversation is not pending' do
        payload = { event: 'message_created', conversation: { id: conversation.id }, id: message.id }

        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found'))

        expect do
          trigger.execute(url, payload, webhook_type)
        end.not_to(change { message.reload.status })

        expect(Conversations::ActivityMessageJob).not_to have_been_enqueued
        expect(conversation.reload.status).to eq('open')
      end

      it 'keeps conversation pending when keep_pending_on_bot_failure setting is enabled' do
        account.update(keep_pending_on_bot_failure: true)
        payload = { event: 'message_created', id: pending_message.id }

        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found'))

        trigger.execute(url, payload, webhook_type)

        expect(Conversations::ActivityMessageJob).not_to have_been_enqueued
        expect(pending_conversation.reload.status).to eq('pending')
      end

      it 'reopens conversation when keep_pending_on_bot_failure setting is disabled' do
        account.update(keep_pending_on_bot_failure: false)
        payload = { event: 'message_created', id: pending_message.id }

        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found'))

        expect do
          perform_enqueued_jobs do
            trigger.execute(url, payload, webhook_type)
          end
        end.not_to(change { pending_message.reload.status })

        expect(pending_conversation.reload.status).to eq('open')

        activity_message = pending_conversation.reload.messages.order(:created_at).last
        expect(activity_message.message_type).to eq('activity')
        expect(activity_message.content).to eq(agent_bot_error_content)
      end
    end

    # DIVERGENCIA DELIBERADA DO UPSTREAM (B3): este exemplo se chamava
    # 'handles 500 without raising for non-agent webhooks' e afirmava exatamente
    # o defeito — engolir o 500 e nunca reentregar. Vai conflitar no proximo
    # merge do upstream, e e para conflitar.
    it 'lets a 500 rise for non-agent webhooks so the job can retry' do
      payload = { event: 'message_created', conversation: { id: conversation.id }, id: message.id }

      expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))

      expect { trigger.execute(url, payload, webhook_type) }
        .to raise_error(SafeFetch::HttpError, '500 Internal Server Error')
      expect(message.reload.status).to eq('sent')
    end
  end

  describe 'request headers' do
    let(:payload) { { event: 'message_created' } }
    let(:body) { payload.to_json }

    context 'without secret or delivery_id' do
      it 'sends only content-type and accept headers' do
        expect(SafeFetch).to receive(:fetch).with(
          url,
          method: :post,
          body: body,
          headers: base_headers,
          open_timeout: webhook_timeout,
          read_timeout: webhook_timeout,
          validate_content_type: false
        ).and_yield(fetch_result)

        trigger.execute(url, payload, webhook_type)
      end
    end

    context 'with delivery_id' do
      it 'adds X-Chatwoot-Delivery header' do
        expect(SafeFetch).to receive(:fetch) do |received_url, **options, &block|
          expect(received_url).to eq(url)
          expect(options[:headers]['X-Chatwoot-Delivery']).to eq('test-uuid')
          expect(options[:headers]).not_to have_key('X-Chatwoot-Signature')
          expect(options[:headers]).not_to have_key('X-Chatwoot-Timestamp')
          block.call(fetch_result)
        end

        trigger.execute(url, payload, webhook_type, delivery: described_class::Delivery.new(id: 'test-uuid'))
      end
    end

    context 'with secret' do
      let(:secret) { 'test-secret' }

      it 'adds X-Chatwoot-Timestamp header' do
        expect(SafeFetch).to receive(:fetch) do |_received_url, **options, &block|
          expect(options[:headers]['X-Chatwoot-Timestamp']).to match(/\A\d+\z/)
          block.call(fetch_result)
        end

        trigger.execute(url, payload, webhook_type, secret: secret)
      end

      it 'adds X-Chatwoot-Signature header with correct HMAC' do
        expect(SafeFetch).to receive(:fetch) do |_received_url, **options, &block|
          ts = options[:headers]['X-Chatwoot-Timestamp']
          expected_sig = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{body}")}"
          expect(options[:headers]['X-Chatwoot-Signature']).to eq(expected_sig)
          block.call(fetch_result)
        end

        trigger.execute(url, payload, webhook_type, secret: secret)
      end

      it 'signs timestamp.body not just body' do
        expect(SafeFetch).to receive(:fetch) do |_received_url, **options, &block|
          wrong_sig = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
          expect(options[:headers]['X-Chatwoot-Signature']).not_to eq(wrong_sig)
          block.call(fetch_result)
        end

        trigger.execute(url, payload, webhook_type, secret: secret)
      end
    end

    context 'with both secret and delivery_id' do
      it 'includes all three security headers' do
        expect(SafeFetch).to receive(:fetch) do |_received_url, **options, &block|
          expect(options[:headers]['X-Chatwoot-Delivery']).to eq('abc-123')
          expect(options[:headers]['X-Chatwoot-Timestamp']).to be_present
          expect(options[:headers]['X-Chatwoot-Signature']).to start_with('sha256=')
          block.call(fetch_result)
        end

        trigger.execute(url, payload, webhook_type, secret: 'mysecret',
                                                    delivery: described_class::Delivery.new(id: 'abc-123'))
      end
    end
  end

  it 'does not update message status if webhook fails for other events' do
    payload = { event: 'conversation_created', conversation: { id: conversation.id }, id: message.id }

    expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))

    expect { trigger.execute(url, payload, webhook_type) }.to raise_error(SafeFetch::HttpError)
    expect(message.reload.status).to eq('sent')
  end

  context 'when webhook timeout configuration is blank' do
    let(:webhook_timeout) { nil }

    it 'falls back to default timeout' do
      expect(SafeFetch).to receive(:fetch).with(
        url,
        method: :post,
        body: payload.to_json,
        headers: base_headers,
        open_timeout: default_timeout,
        read_timeout: default_timeout,
        validate_content_type: false
      ).and_yield(fetch_result)

      trigger.execute(url, payload, webhook_type)
    end
  end

  context 'when webhook timeout configuration is invalid' do
    let(:webhook_timeout) { -1 }

    it 'falls back to default timeout' do
      expect(SafeFetch).to receive(:fetch).with(
        url,
        method: :post,
        body: payload.to_json,
        headers: base_headers,
        open_timeout: default_timeout,
        read_timeout: default_timeout,
        validate_content_type: false
      ).and_yield(fetch_result)

      trigger.execute(url, payload, webhook_type)
    end
  end
end
