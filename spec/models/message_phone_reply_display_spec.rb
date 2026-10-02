require 'rails_helper'

RSpec.describe Message do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account), waha_session_name: 'phone') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:body) { "#{described_class::WHATSAPP_PHONE_REPLY_MARKER}\n\n💬 **Mensagem (às 15:12):**\n\"Olá!\nTudo bem?\"" }
  let(:message) { create(:message, conversation: conversation, private: true, message_type: :outgoing, content: body) }

  def rest_payload
    JSON.parse(ApplicationController.render(partial: 'api/v1/models/message', formats: [:json], locals: { message: message }))
  end

  it 'exposes the phone reply and clean body through REST and websocket without changing storage' do
    [rest_payload, message.push_event_data.deep_stringify_keys].each do |payload|
      expect(payload['content_attributes']).to include('whatsapp_phone_reply' => true, 'whatsapp_phone_reply_content' => "Olá!\nTudo bem?")
      expect(payload['private']).to be true
      expect(payload['content']).to eq(body)
    end
    expect(message.reload.content_attributes).not_to have_key('whatsapp_phone_reply')
    expect(message.content).to eq(body)
  end

  it 'preserves a body without the WAHA message wrapper' do
    message.update!(content: "#{described_class::WHATSAPP_PHONE_REPLY_MARKER}\n\n\"Texto citado\"")
    expect(rest_payload['content_attributes']['whatsapp_phone_reply_content']).to eq('"Texto citado"')
  end

  it 'strips the wrapper without a timestamp' do
    message.update!(content: "#{described_class::WHATSAPP_PHONE_REPLY_MARKER}\n\n💬 **Mensagem:**\n\"Oi\"")
    expect(rest_payload['content_attributes']['whatsapp_phone_reply_content']).to eq('Oi')
  end

  it 'does not mark ordinary private notes' do
    message.update!(content: 'Nota interna')
    [rest_payload, message.push_event_data.deep_stringify_keys].each do |payload|
      expect(payload['content_attributes']).not_to have_key('whatsapp_phone_reply')
    end
  end

  it 'does not mark notes outside WAHA even when they contain the marker' do
    inbox.update!(waha_session_name: nil)
    expect(rest_payload['content_attributes']).not_to have_key('whatsapp_phone_reply')
  end
end
