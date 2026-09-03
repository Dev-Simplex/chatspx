require 'rails_helper'

# Bloco 4.12 — `conversation_resolved` no webhook de CONTA.
#
# Ate aqui o evento existia so para agent bot (agent_bot_listener.rb:2). Webhook de conta
# nao podia nem se inscrever nele: o nome nao estava em ALLOWED_WEBHOOK_EVENTS, entao a
# validacao do modelo recusava a inscricao.
RSpec.describe WebhookListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:event) { Events::Base.new('conversation.resolved', Time.zone.now, { conversation: conversation }) }

  describe 'inscricao no evento' do
    it 'o modelo aceita conversation_resolved' do
      webhook = build(:webhook, account: account, subscriptions: ['conversation_resolved'])

      expect(webhook).to be_valid
    end
  end

  describe '#conversation_resolved' do
    let!(:webhook) do
      create(:webhook, account: account, url: 'https://destino.exemplo.com/hook',
                       subscriptions: %w[conversation_resolved])
    end

    it 'entrega o payload ao webhook de conta inscrito' do
      expect { listener.conversation_resolved(event) }
        .to have_enqueued_job(WebhookJob)
        .with('https://destino.exemplo.com/hook', hash_including(event: 'conversation_resolved'), :account_webhook,
              hash_including(:secret, :delivery_id))
    end

    # O aceite pede as duas coisas explicitamente: sem assinatura o destino nao consegue
    # provar que o payload veio de nos, e sem delivery id ele nao consegue deduplicar.
    it 'entrega COM assinatura e COM delivery id, e nao com nil' do
      capturado = nil
      allow(WebhookJob).to receive(:perform_later) { |*args| capturado = args }

      listener.conversation_resolved(event)

      url, payload, tipo, kwargs = capturado
      expect(url).to eq('https://destino.exemplo.com/hook')
      expect(tipo).to eq(:account_webhook)
      expect(payload[:event]).to eq('conversation_resolved')
      expect(kwargs[:secret]).to eq(webhook.secret)
      expect(kwargs[:secret]).to be_present
      expect(kwargs[:delivery_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'o payload identifica a conversa resolvida' do
      capturado = nil
      allow(WebhookJob).to receive(:perform_later) { |*args| capturado = args }

      listener.conversation_resolved(event)

      expect(capturado[1][:id]).to eq(conversation.display_id)
    end

    it 'nao entrega a webhook que nao se inscreveu no evento' do
      webhook.update!(subscriptions: ['conversation_created'])

      expect { listener.conversation_resolved(event) }.not_to have_enqueued_job(WebhookJob)
    end
  end
end
