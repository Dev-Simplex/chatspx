require 'rails_helper'

RSpec.describe WebhookJob do
  include ActiveJob::TestHelper

  subject(:job) { described_class.perform_later(url, payload, webhook_type) }

  let(:url) { 'https://test.chatwoot.com' }
  let(:payload) { { name: 'test' } }
  let(:webhook_type) { :account_webhook }

  it 'queues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(url, payload, webhook_type)
      .on_queue('medium')
  end

  it 'executes perform with default webhook type' do
    expect(Webhooks::Trigger).to receive(:execute).with(url, payload, webhook_type, secret: nil, delivery: kind_of(Webhooks::Trigger::Delivery))
    perform_enqueued_jobs { job }
  end

  context 'with custom webhook type' do
    let(:webhook_type) { :api_inbox_webhook }

    it 'executes perform with inbox webhook type' do
      expect(Webhooks::Trigger).to receive(:execute).with(url, payload, webhook_type, secret: nil, delivery: kind_of(Webhooks::Trigger::Delivery))
      perform_enqueued_jobs { job }
    end
  end

  # B3 — o webhook que dizia que entregou.
  #
  # `retry_on StandardError, attempts: 5` estava declarado desde sempre, mas
  # `Webhooks::Trigger#execute` engolia a excecao: o job terminava com sucesso e
  # as 5 tentativas nunca aconteciam. Estes exemplos medem as tres pontas do
  # aceite — quantas tentativas, com que delivery id, e quando o efeito
  # colateral morde.
  describe 'retry de entrega' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }
    let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
    let(:payload) { { event: 'message_created', conversation: { id: conversation.id }, id: message.id } }
    let(:webhook_type) { :api_inbox_webhook }
    let(:attempts) { [] }

    def stub_fetch_raising(error)
      allow(SafeFetch).to receive(:fetch) do |_fetch_url, **options|
        attempts << { delivery: options[:headers]['X-Chatwoot-Delivery'], message_status: message.reload.status }
        raise error
      end
    end

    before do
      ActiveJob::Base.queue_adapter = :test
      message # materializa antes de qualquer tentativa
    end

    after do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    it 'tenta 5 vezes com o mesmo delivery id e marca a mensagem falha uma unica vez, no esgotamento' do
      stub_fetch_raising(SafeFetch::HttpError.new('500 Internal Server Error'))

      perform_enqueued_jobs do
        described_class.perform_later(url, payload, webhook_type, delivery_id: 'entrega-fixa-42')
      end

      expect(attempts.length).to eq(5)
      expect(attempts.map { |attempt| attempt[:delivery] }).to eq(['entrega-fixa-42'] * 5)
      # Enquanto havia reentrega pela frente, a mensagem seguia 'sent'. Se
      # handle_failure rodasse a cada tentativa, a 2a ja leria 'failed'.
      expect(attempts.map { |attempt| attempt[:message_status] }).to eq(%w[sent sent sent sent sent])
      expect(message.reload.status).to eq('failed')
    end

    it 'usa um delivery id estavel entre as tentativas quando o chamador nao informa nenhum' do
      stub_fetch_raising(SafeFetch::HttpError.new('503 Service Unavailable'))

      perform_enqueued_jobs do
        described_class.perform_later(url, payload, webhook_type)
      end

      deliveries = attempts.map { |attempt| attempt[:delivery] }
      expect(deliveries.length).to eq(5)
      expect(deliveries.uniq.length).to eq(1)
      expect(deliveries.first).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'nao reentrega um 404 — o destino recusou o payload' do
      stub_fetch_raising(SafeFetch::HttpError.new('404 Not Found'))

      perform_enqueued_jobs do
        described_class.perform_later(url, payload, webhook_type, delivery_id: 'entrega-fixa-404')
      end

      expect(attempts.length).to eq(1)
      expect(message.reload.status).to eq('failed')
    end

    # SAFE_FETCH_ALLOW_PRIVATE_NETWORK tem default false (safe_fetch.rb:39):
    # todo webhook para IP privado passou a falhar depois do merge. Reentregar 5
    # vezes, com backoff polinomial, so multiplicaria uma falha de configuracao.
    it 'nao reentrega destino barrado pelo filtro SSRF' do
      stub_fetch_raising(SafeFetch::UnsafeUrlError.new('Blocked private address'))

      perform_enqueued_jobs do
        described_class.perform_later(url, payload, webhook_type, delivery_id: 'entrega-fixa-ssrf')
      end

      expect(attempts.length).to eq(1)
      expect(message.reload.status).to eq('failed')
    end
  end
end
