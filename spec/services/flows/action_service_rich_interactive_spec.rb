# frozen_string_literal: true

require 'rails_helper'

# Extras interativos "ricos" (F3): send_cta_url (botão de link) e send_location_request (pedir
# localização). Espelham send_message/send_interactive — texto de serviço livre (utility, free_form),
# exigem a janela de 24h. Cada ação persiste o objeto `interactive` Meta CRU em
# content_attributes['interactive_payload'] (chave livre; content_type fica 'text'); o provider roteia
# pelo payload. Sem HTTP real — o MessageBuilder só cria a Message.
RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              sync_templates: false, validate_provider_config: false)
  end
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
  let(:contact) { conversation.contact }
  let(:service) { described_class.new(flow: flow, conversation: conversation) }

  after { Current.reset }

  def run(name, params)
    service.execute({ 'type' => 'action', 'action_name' => name, 'action_params' => params })
  end

  # Abre a janela de 24h (a conversa WhatsApp nasce fora dela) com um incoming recente do contato.
  def open_window!
    create(:message, conversation: conversation, account: account, inbox: whatsapp_channel.inbox,
                     message_type: :incoming, content: 'oi', sender: contact)
  end

  def last_outgoing
    conversation.reload.messages.where(message_type: :outgoing).last
  end

  describe '#send_cta_url' do
    let(:params) { [{ 'body' => 'Confira a promo', 'button_text' => 'Abrir site', 'url' => 'https://example.com/promo' }] }

    context 'when inside the 24h window' do
      before { open_window! }

      it 'persists a Message with the Meta cta_url interactive_payload and content_type text' do
        result = run('send_cta_url', params)

        expect(result.status).to eq(:success)
        message = last_outgoing
        expect(message.content_type).to eq('text')
        expect(message.content).to eq('Confira a promo')
        expect(message.content_attributes['interactive_payload']).to eq(
          'type' => 'cta_url',
          'body' => { 'text' => 'Confira a promo' },
          'action' => { 'name' => 'cta_url', 'parameters' => { 'display_text' => 'Abrir site', 'url' => 'https://example.com/promo' } }
        )
      end

      it 'renders Liquid in the body/button/url before assembling the payload' do
        contact.update!(name: 'Ana')
        run('send_cta_url', [{ 'body' => 'Oi {{contact.name}}', 'button_text' => 'Ver {{contact.name}}',
                               'url' => 'https://x.com/u/{{contact.id}}' }])
        payload = last_outgoing.content_attributes['interactive_payload']
        expect(payload.dig('body', 'text')).to eq('Oi Ana')
        expect(payload.dig('action', 'parameters', 'display_text')).to eq('Ver Ana')
        expect(payload.dig('action', 'parameters', 'url')).to eq("https://x.com/u/#{contact.id}")
      end

      it 'includes optional header and footer when present' do
        run('send_cta_url', [{ 'body' => 'b', 'button_text' => 'go', 'url' => 'https://x.com', 'header' => 'H', 'footer' => 'F' }])
        payload = last_outgoing.content_attributes['interactive_payload']
        expect(payload['header']).to eq('type' => 'text', 'text' => 'H')
        expect(payload['footer']).to eq('text' => 'F')
      end

      it 'stamps the flow_id anti-loop marker alongside the interactive_payload' do
        run('send_cta_url', params)
        expect(last_outgoing.content_attributes['flow_id']).to eq(flow.id)
      end

      it 'skips cta_url_incomplete when button_text is missing' do
        result = run('send_cta_url', [{ 'body' => 'b', 'url' => 'https://x.com' }])
        expect(result.status).to eq(:skipped)
        expect(result.error.code).to eq('cta_url_incomplete')
      end

      it 'skips cta_url_incomplete when the url is not http(s)' do
        result = run('send_cta_url', [{ 'body' => 'b', 'button_text' => 'go', 'url' => 'ftp://x.com' }])
        expect(result.status).to eq(:skipped)
        expect(result.error.code).to eq('cta_url_incomplete')
      end

      it 'does not create a Message when skipped' do
        expect { run('send_cta_url', [{ 'body' => 'b' }]) }.not_to change(Message, :count)
      end
    end

    it 'skips inbox_not_whatsapp when the inbox is not WhatsApp Cloud' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))
      svc = described_class.new(flow: flow, conversation: other)
      result = svc.execute({ 'type' => 'action', 'action_name' => 'send_cta_url', 'action_params' => params })
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('inbox_not_whatsapp')
    end

    it 'skips outside_window (compliance) with a valid config outside the 24h window' do
      result = run('send_cta_url', params)
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('outside_window')
    end
  end

  describe '#send_location_request' do
    context 'when inside the 24h window' do
      before { open_window! }

      it 'persists a Message with the Meta location_request_message interactive_payload' do
        result = run('send_location_request', [{ 'body' => 'Onde você está?' }])

        expect(result.status).to eq(:success)
        message = last_outgoing
        expect(message.content_type).to eq('text')
        expect(message.content).to eq('Onde você está?')
        expect(message.content_attributes['interactive_payload']).to eq(
          'type' => 'location_request_message',
          'body' => { 'text' => 'Onde você está?' },
          'action' => { 'name' => 'send_location' }
        )
      end

      it 'skips location_request_incomplete when body is blank' do
        result = run('send_location_request', [{ 'body' => '  ' }])
        expect(result.status).to eq(:skipped)
        expect(result.error.code).to eq('location_request_incomplete')
      end

      it 'does not create a Message when skipped' do
        expect { run('send_location_request', [{}]) }.not_to change(Message, :count)
      end
    end

    it 'skips inbox_not_whatsapp when the inbox is not WhatsApp Cloud' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))
      svc = described_class.new(flow: flow, conversation: other)
      result = svc.execute({ 'type' => 'action', 'action_name' => 'send_location_request', 'action_params' => [{ 'body' => 'x' }] })
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('inbox_not_whatsapp')
    end

    it 'skips outside_window outside the 24h window' do
      result = run('send_location_request', [{ 'body' => 'x' }])
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('outside_window')
    end
  end
end
