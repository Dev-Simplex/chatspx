# frozen_string_literal: true

require 'rails_helper'

# Compliance guards do gap-BR (WhatsApp marketing): opt-out (PARAR), cap de marketing/dia e a
# janela de 24h — aplicados IMEDIATAMENTE antes de send_message/send_template enviarem. Cada
# bloqueio vira um Flows::StepSkip tipado (skipped, sem Sentry) que o Runner registra.
RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }
  # Um template MARKETING e um UTILITY, ambos aprovados, na mesma inbox WhatsApp Cloud.
  let(:templates) do
    [
      { 'name' => 'promo_marketing', 'status' => 'approved', 'category' => 'MARKETING', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oferta imperdível!' }] },
      { 'name' => 'ticket_update', 'status' => 'approved', 'category' => 'UTILITY', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Chamado atualizado.' }] }
    ]
  end
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              sync_templates: false, validate_provider_config: false, message_templates: templates)
  end
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
  let(:contact) { conversation.contact }
  let(:marketing_template) do
    { 'name' => 'promo_marketing', 'language' => 'pt_BR', 'content' => 'Oferta imperdível!', 'processed_params' => {} }
  end
  let(:utility_template) do
    { 'name' => 'ticket_update', 'language' => 'pt_BR', 'content' => 'Chamado atualizado.', 'processed_params' => {} }
  end
  let(:service) { described_class.new(flow: flow, conversation: conversation) }

  after { Current.reset }

  def run(service, name, params)
    service.execute({ 'type' => 'action', 'action_name' => name, 'action_params' => params })
  end

  # A conversa WhatsApp nasce SEM incoming → fora da janela de 24h por padrão. Abre a janela
  # criando uma mensagem incoming recente do contato.
  def open_window!
    create(:message, conversation: conversation, account: account, inbox: whatsapp_channel.inbox,
                     message_type: :incoming, content: 'oi', sender: contact)
  end

  # Simula um envio de MARKETING passado ao contato (para o cap): mensagem outgoing carregando
  # o template_params do template de marketing.
  def past_marketing_send(created_at: Time.current)
    message = create(:message, conversation: conversation, account: account, inbox: whatsapp_channel.inbox,
                               message_type: :outgoing, content: 'Oferta',
                               additional_attributes: { 'template_params' => { 'name' => 'promo_marketing' } })
    message.update_column(:created_at, created_at) # rubocop:disable Rails/SkipsModelValidations
    message
  end

  describe 'opt-out guard (suppressed_opt_out)' do
    before { open_window! }

    it 'skips a MARKETING template when the contact has an active marketing suppression' do
      ContactFlowSuppression.record_opt_out!(contact: contact, account: account)
      result = nil
      expect { result = run(service, 'send_template', [marketing_template]) }.not_to change(Message, :count)
      expect(result.status).to eq(:skipped)
      expect(result.error).to be_a(Flows::StepSkip).and(have_attributes(code: 'suppressed_opt_out'))
    end

    it 'still delivers a UTILITY template — a marketing opt-out does not block utility (R-6)' do
      ContactFlowSuppression.record_opt_out!(contact: contact, account: account)
      expect { run(service, 'send_template', [utility_template]) }.to change(Message, :count).by(1)
    end

    it 'an `all` suppression blocks even a UTILITY template' do
      create(:contact_flow_suppression, contact: contact, account: account, category: 'all')
      result = nil
      expect { result = run(service, 'send_template', [utility_template]) }.not_to change(Message, :count)
      expect(result.error.code).to eq('suppressed_opt_out')
    end
  end

  describe 'marketing cap guard (marketing_cap)' do
    before { open_window! }

    it 'skips a MARKETING template once the daily cap (default 1) is reached' do
      past_marketing_send
      result = nil
      expect { result = run(service, 'send_template', [marketing_template]) }.not_to change(Message, :count)
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('marketing_cap')
    end

    it 'delivers the FIRST marketing message of the window (count below cap)' do
      expect { run(service, 'send_template', [marketing_template]) }.to change(Message, :count).by(1)
    end

    it 'does NOT count a UTILITY send toward the marketing cap (R-6): utility still delivers' do
      past_marketing_send # 1 marketing already; cap = 1
      expect { run(service, 'send_template', [utility_template]) }.to change(Message, :count).by(1)
    end

    it 'ignores marketing sends older than the 24h window' do
      past_marketing_send(created_at: 25.hours.ago)
      expect { run(service, 'send_template', [marketing_template]) }.to change(Message, :count).by(1)
    end

    it 'honours a per-account cap override (internal_attributes)' do
      account.update!(internal_attributes: account.internal_attributes.merge('flows_marketing_daily_cap' => 2))
      past_marketing_send # 1 marketing; override cap = 2 → still allowed
      expect { run(service, 'send_template', [marketing_template]) }.to change(Message, :count).by(1)
    end
  end

  describe '24h window guard (outside_window)' do
    it 'skips a free-form send_message outside the window (no incoming message yet)' do
      result = nil
      expect { result = run(service, 'send_message', ['Olá!']) }.not_to change(Message, :count)
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('outside_window')
    end

    it 'delivers a free-form send_message inside the window' do
      open_window!
      expect { run(service, 'send_message', ['Olá!']) }.to change { conversation.messages.where(message_type: :outgoing).count }.by(1)
    end

    it 'delivers a TEMPLATE outside the window — templates are the point of being out-of-window' do
      # janela fechada (sem incoming), sem suppression, sem cap → o template SAI
      expect { run(service, 'send_template', [marketing_template]) }.to change(Message, :count).by(1)
    end

    it 'does not gate free-form on channels without a messaging window (web widget → can_reply? true)' do
      web_conversation = create(:conversation, account: account, inbox: create(:inbox, account: account))
      web_service = described_class.new(flow: flow, conversation: web_conversation)
      expect { run(web_service, 'send_message', ['Olá!']) }.to change(Message, :count).by(1)
    end
  end
end
