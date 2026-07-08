require 'rails_helper'

# Nó send_whatsapp_flow — TODO DOCUMENTADO (envio de WhatsApp Flow interactive pendente de
# integração no provider). A ação faz a parte SEGURA (valida inbox cloud + compliance + monta o
# payload Meta) e sinaliza um skip triável em vez de enviar errado. NÃO está na whitelist/paleta.
RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }

  after { Current.reset }

  def action(params)
    { 'type' => 'action', 'action_name' => 'send_whatsapp_flow', 'action_params' => [params] }
  end

  describe '#send_whatsapp_flow' do
    let(:whatsapp_channel) do
      create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false)
    end
    let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }

    def run(conv, params)
      described_class.new(flow: flow, conversation: conv).execute(action(params))
    end

    it 'skips with whatsapp_flow_provider_missing on a cloud inbox with a valid config (payload assembled, not sent)' do
      allow(conversation).to receive(:can_reply?).and_return(true) # dentro da janela de 24h
      result = run(conversation, 'flow_id' => 'meta_flow_123', 'cta' => 'Abrir', 'body' => 'Olá {{contact.name}}')
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('whatsapp_flow_provider_missing')
    end

    it 'skips inbox_not_whatsapp when the inbox is not WhatsApp Cloud' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))
      result = run(other, 'flow_id' => 'x', 'cta' => 'y', 'body' => 'z')
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('inbox_not_whatsapp')
    end

    it 'skips whatsapp_flow_incomplete when flow_id/cta/body is missing' do
      result = run(conversation, 'flow_id' => 'x') # falta cta/body
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('whatsapp_flow_incomplete')
    end

    it 'is NOT in the community whitelist (integration pending — must not be buildable in a flow)' do
      expect(Flow::BASE_ACTION_NAMES).not_to include('send_whatsapp_flow')
    end

    it 'builds the Meta interactive flow payload in the correct shape' do
      service = described_class.new(flow: flow, conversation: conversation)
      payload = service.send(:build_whatsapp_flow_payload,
                             { 'flow_id' => 'F1', 'cta' => 'Start', 'body' => 'Hi',
                               'header' => 'H', 'footer' => 'Ft', 'screen' => 'WELCOME' }.with_indifferent_access)
      expect(payload).to match(
        type: 'flow',
        body: { text: 'Hi' },
        header: { type: 'text', text: 'H' },
        footer: { text: 'Ft' },
        action: { name: 'flow', parameters: {
          flow_message_version: '3', flow_token: be_present, flow_id: 'F1',
          flow_cta: 'Start', flow_action: 'navigate', flow_action_payload: { screen: 'WELCOME' }
        } }
      )
    end
  end
end
