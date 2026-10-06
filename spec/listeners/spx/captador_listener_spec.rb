require 'rails_helper'

# Eventos das conversas do Captador (22 §1.5), assinados com o segredo do hook pelo WebhookJob.
RSpec.describe Spx::CaptadorListener do
  include CaptadorSigningHelpers

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let!(:hook) { captador_hook_for(account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, custom_attributes: { 'captador_lead_id' => 'lead-1' }) }
  let(:url) { 'https://captador.spx.ia.br/webhooks/chatspx/inst-1' }

  before { stub_captador_dns }

  def event(name, data)
    Events::Base.new(name, Time.zone.now, data)
  end

  def message(**attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation, **attrs)
  end

  def expect_delivery(payload)
    expect(WebhookJob).to receive(:perform_later)
      .with(url, hash_including(payload), :account_webhook, secret: hook.captador_shared_secret, delivery_id: kind_of(String))
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

    it 'não entrega conversa sem carimbo de caixa que não está liberada' do
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

    it 'não enfileira para destino fora de CAPTADOR_HOSTS_PERMITIDOS (SSRF)' do
      incoming = message
      hook.update!(settings: hook.settings.merge('captador_url' => 'https://169.254.169.254'))
      expect(WebhookJob).not_to receive(:perform_later)

      listener.message_created(event('message.created', message: incoming))
    end

    it 'não enfileira quando o host permitido resolve para IP interno' do
      incoming = message
      stub_captador_dns('10.0.0.5')
      expect(WebhookJob).not_to receive(:perform_later)

      listener.message_created(event('message.created', message: incoming))
    end

    it 'não deixa exceção escapar para os listeners seguintes' do
      incoming = message
      allow(incoming).to receive(:webhook_data).and_raise(StandardError, 'boom')

      expect { listener.message_created(event('message.created', message: incoming)) }.not_to raise_error
    end
  end

  # Conversa aberta direto no ChatSPX: o Captador liga ao lead pelo telefone do contato.
  describe 'conversa sem carimbo' do
    let(:released) { create(:channel_api, account: account).inbox }
    let(:contact) { create(:contact, account: account, phone_number: '+5565999998888') }
    let(:conversation) { create(:conversation, account: account, inbox: released, contact: contact) }

    def direct_message(**attrs)
      create(:message, account: account, inbox: conversation.inbox, conversation: conversation, **attrs)
    end

    before { hook.update!(settings: hook.settings.merge('allowed_inbox_ids' => released.id.to_s)) }

    def resolved(conv)
      event('conversation.status_changed', conversation: conv, changed_attributes: { status: %w[open resolved] })
    end

    it 'entrega a mensagem de caixa liberada com o telefone do contato e a caixa' do
      incoming = direct_message(message_type: 'incoming', content: 'Oi, quero um orçamento')
      sender = hash_including(id: contact.id, phone_number: '+5565999998888')
      expect_delivery(event: 'message_created', id: incoming.id,
                      conversation: hash_including(id: conversation.display_id, inbox_id: released.id, meta: hash_including(sender: sender)))

      listener.message_created(event('message.created', message: incoming))
    end

    it 'entrega a conversa resolvida de caixa liberada' do
      expect_delivery(event: 'conversation_status_changed', id: conversation.display_id, inbox_id: released.id)

      listener.conversation_status_changed(resolved(conversation))
    end

    it 'ignora nota privada' do
      note = direct_message(message_type: 'outgoing', private: true)
      expect(WebhookJob).not_to receive(:perform_later)

      listener.message_created(event('message.created', message: note))
    end

    it 'ignora caixa fora de allowed_inbox_ids' do
      other = create(:conversation, account: account, inbox: create(:channel_api, account: account).inbox, contact: contact)
      incoming = create(:message, account: account, inbox: other.inbox, conversation: other, message_type: 'incoming')
      expect(WebhookJob).not_to receive(:perform_later)

      listener.message_created(event('message.created', message: incoming))
      listener.conversation_status_changed(resolved(other))
    end
  end

  # Despacho real: o save do model enfileira o EventDispatcherJob, que roda aqui como no Sidekiq (o
  # event data passa pela serialização do ActiveJob). O WebhookJob só é enfileirado, para conferir o
  # que sairia para o Captador. O registro chega criado: o argumento é avaliado antes do bloco.
  def save_for_real(record, **attributes)
    perform_enqueued_jobs(only: EventDispatcherJob) { record.update!(**attributes) }
  end

  def expect_captador_job(**payload)
    expect(WebhookJob).to have_been_enqueued.once.with(
      url, hash_including(payload), :account_webhook, secret: hook.captador_shared_secret, delivery_id: kind_of(String)
    )
  end

  def status_change(previous, current)
    include('status' => { previous_value: previous, current_value: current })
  end

  describe '#message_updated (Message#update! real)' do
    let(:outgoing) { message(message_type: 'outgoing') }

    it 'entrega a falha de envio com o motivo em content_attributes.external_error' do
      save_for_real(outgoing, status: :failed, external_error: '131026: Message undeliverable')

      expect_captador_job(event: 'message_updated', id: outgoing.id, changed_attributes: status_change('sent', 'failed'),
                          content_attributes: hash_including('external_error' => '131026: Message undeliverable'),
                          conversation: hash_including(id: conversation.display_id))
    end

    it 'entrega entregue e depois lida' do
      save_for_real(outgoing, status: :delivered)
      save_for_real(outgoing, status: :read)

      expect_captador_job(event: 'message_updated', id: outgoing.id, changed_attributes: status_change('sent', 'delivered'))
      expect_captador_job(event: 'message_updated', id: outgoing.id, changed_attributes: status_change('delivered', 'read'))
    end

    it 'ignora mudança que não é de status' do
      save_for_real(outgoing, content: 'editada')

      expect(WebhookJob).not_to have_been_enqueued
    end
  end

  describe 'eventos da conversa (Conversation#update! real)' do
    let(:agent) { create(:user, account: account, role: :agent) }

    # Resolver exige time (Conversation#team_required_for_resolution).
    before do
      conversation.update!(team: create(:team, account: account))
      create(:inbox_member, inbox: inbox, user: agent)
    end

    it 'entrega conversa resolvida' do
      save_for_real(conversation, status: :resolved)

      expect_captador_job(event: 'conversation_status_changed', id: conversation.display_id, status: 'resolved')
      expect(WebhookJob).to have_been_enqueued.once
    end

    it 'entrega a troca de dono uma vez só' do
      save_for_real(conversation, assignee: agent)

      expect_captador_job(event: 'conversation_updated', id: conversation.display_id,
                          meta: hash_including(assignee: hash_including(name: agent.name)))
      expect(WebhookJob).to have_been_enqueued.once
    end

    it 'entrega a troca de dono feita no mesmo save que resolve (o model não despacha conversation.updated)' do
      save_for_real(conversation, status: :resolved, assignee: agent)

      expect_captador_job(event: 'conversation_status_changed', status: 'resolved')
      expect_captador_job(event: 'conversation_updated', id: conversation.display_id,
                          meta: hash_including(assignee: hash_including(name: agent.name)))
      expect(WebhookJob).to have_been_enqueued.twice
    end

    it 'ignora atualização que não mexe em dono, time nem status' do
      save_for_real(conversation, priority: :high)

      expect(WebhookJob).not_to have_been_enqueued
    end
  end
end
