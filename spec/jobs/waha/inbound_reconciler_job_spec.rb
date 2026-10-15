require 'rails_helper'

RSpec.describe Waha::InboundReconcilerJob do
  let(:api_channel) { create(:channel_api) }
  let(:inbox) { api_channel.inbox }
  let(:waha) { instance_double(Waha::ApiService) }

  before do
    inbox.update!(waha_session_name: 'Simplex')
    allow(Waha::ApiService).to receive(:new).and_return(waha)
    allow(waha).to receive(:get_messages).and_return([{ 'id' => 'wamid-1', 'body' => 'story', 'fromMe' => false }])
  end

  def conversation_for(chat_id)
    contact = create(:contact, account: inbox.account, custom_attributes: { 'waha_whatsapp_chat_id' => chat_id })
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    create(:conversation, account: inbox.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  # CHAT-170: status e listas de transmissão não são atendimento.
  it 'não reinjeta mensagem em conversa @broadcast' do
    conversation = conversation_for('status@broadcast')

    with_modified_env WAHA_RECONCILER_ENABLED: 'true' do
      described_class.perform_now
    end

    expect(waha).not_to have_received(:get_messages)
    expect(conversation.messages).to be_empty
  end

  it 'reinjeta a mensagem que faltou numa conversa comum' do
    conversation = conversation_for('5566999991234@c.us')

    with_modified_env WAHA_RECONCILER_ENABLED: 'true' do
      described_class.perform_now
    end

    expect(conversation.messages.pluck(:content)).to eq(['story'])
  end
end
