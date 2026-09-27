require 'rails_helper'

# Eventos das conversas do Captador (22 §1.5), assinados com o segredo do hook pelo WebhookJob.
RSpec.describe Spx::CaptadorListener do
  include CaptadorSigningHelpers

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let!(:hook) { captador_hook_for(account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, custom_attributes: { 'captador_lead_id' => 'lead-1' }) }
  let(:url) { 'https://captador.test/webhooks/chatspx/inst-1' }

  def event(name, data)
    Events::Base.new(name, Time.zone.now, data)
  end

  def message(**attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation, **attrs)
  end

  def expect_delivery(payload)
    expect(WebhookJob).to receive(:perform_later)
      .with(url, hash_including(payload), :account_webhook, secret: hook.settings['shared_secret'], delivery_id: kind_of(String))
  end

  describe '#message_created' do
    it 'entrega a resposta do lead com o payload do webhook de conta' do
      incoming = message(message_type: 'incoming', content: 'Tenho interesse, me liga')
      expect_delivery(event: 'message_created', id: incoming.id, message_type: 'incoming')

      listener.message_created(event('message.created', message: incoming))
    end

    it 'marca opt_out quando o lead recusa' do
      refusal = message(message_type: 'incoming', content: 'PARAR')
      expect_delivery(event: 'message_created', captador: { opt_out: true })

      listener.message_created(event('message.created', message: refusal))
    end

    it 'entrega a resposta do vendedor' do
      reply = message(message_type: 'outgoing', content: 'Oi!')
      expect_delivery(event: 'message_created', message_type: 'outgoing')

      listener.message_created(event('message.created', message: reply))
    end

    it 'ignora nota privada' do
      note = message(message_type: 'outgoing', private: true)
      expect(WebhookJob).not_to receive(:perform_later)

      listener.message_created(event('message.created', message: note))
    end

    it 'não entrega conversa que não é do Captador' do
      incoming = message
      conversation.update!(custom_attributes: {})
      expect(WebhookJob).not_to receive(:perform_later)

      listener.message_created(event('message.created', message: incoming))
    end

    it 'não entrega com o interruptor da conta desligado' do
      incoming = message
      account.update!(captador_integration: false)
      expect(WebhookJob).not_to receive(:perform_later)

      listener.message_created(event('message.created', message: incoming))
    end

    it 'não deixa exceção escapar para os listeners seguintes' do
      incoming = message
      allow(incoming).to receive(:webhook_data).and_raise(StandardError, 'boom')

      expect { listener.message_created(event('message.created', message: incoming)) }.not_to raise_error
    end
  end

  describe '#message_updated' do
    it 'entrega mudança de status (entregue, lida, falhou)' do
      outgoing = message(message_type: 'outgoing')
      expect_delivery(event: 'message_updated', changed_attributes: [{ 'status' => { previous_value: 'sent', current_value: 'failed' } }])

      listener.message_updated(event('message.updated', message: outgoing, changed_attributes: { 'status' => %w[sent failed] }))
    end

    it 'ignora mudança que não é de status' do
      edited = message
      expect(WebhookJob).not_to receive(:perform_later)

      listener.message_updated(event('message.updated', message: edited, changed_attributes: { 'content' => %w[a b] }))
    end
  end

  describe 'eventos da conversa' do
    it 'entrega conversa resolvida ou reaberta' do
      expect_delivery(event: 'conversation_status_changed', id: conversation.display_id)

      listener.conversation_status_changed(event('conversation.status_changed', conversation: conversation,
                                                                                changed_attributes: { 'status' => %w[open resolved] }))
    end

    it 'entrega troca de dono ou de time' do
      expect_delivery(event: 'conversation_updated', id: conversation.display_id)

      listener.conversation_updated(event('conversation.updated', conversation: conversation, changed_attributes: { 'team_id' => [nil, 7] }))
    end

    it 'ignora atualização que não mexe em dono nem time' do
      expect(WebhookJob).not_to receive(:perform_later)

      listener.conversation_updated(event('conversation.updated', conversation: conversation, changed_attributes: { 'label_list' => [[], ['x']] }))
    end
  end
end
