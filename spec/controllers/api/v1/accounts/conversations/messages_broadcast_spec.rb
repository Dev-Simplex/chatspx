require 'rails_helper'

# CHAT-170: a app `chatwoot` da WAHA cria a conversa pela API pública, mas posta as mensagens pela
# API de conta, no id da conversa que guardou. Uma conversa de status/lista de transmissão que já
# existia seguia recebendo stories por aqui, sem passar pelo filtro da API pública.
RSpec.describe 'Conversation Messages API — chats @broadcast do WhatsApp', type: :request do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:agent) { create(:user, account: account, role: :administrator) }

  before { inbox.update!(waha_session_name: 'Simplex') }

  def conversation_for(contact)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def post_incoming(conversation, content)
    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
         params: { content: content, message_type: 'incoming' },
         headers: agent.create_new_auth_token,
         as: :json
  end

  context 'com o contato status@broadcast' do
    let(:contact) do
      create(:contact, account: account, identifier: 'status@broadcast',
                       custom_attributes: { 'waha_whatsapp_chat_id' => 'status@broadcast' })
    end
    let!(:conversation) { conversation_for(contact) }

    it 'não cria a mensagem' do
      expect { post_incoming(conversation, 'story') }.not_to change(Message, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('status' => 'suppressed', 'reason' => 'whatsapp_broadcast')
    end

    it 'não cria nota privada da app da WAHA' do
      post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
           params: { content: 'A mensagem tem mídia, mas não conseguimos fazer o download', private: true },
           headers: agent.create_new_auth_token,
           as: :json

      expect(conversation.messages.count).to eq(0)
    end
  end

  context 'com uma lista de transmissão' do
    let(:contact) do
      create(:contact, account: account, identifier: '1640005907@broadcast', name: 'Lista de transmissão',
                       custom_attributes: { 'waha_whatsapp_chat_id' => '1640005907@broadcast' })
    end
    let!(:conversation) { conversation_for(contact) }

    it 'não cria a mensagem' do
      expect { post_incoming(conversation, 'promoção') }.not_to change(Message, :count)
    end

    it 'reconhece pelo custom_attributes quando o identifier não veio' do
      contact.update!(identifier: nil, custom_attributes: { 'waha_whatsapp_jid' => '1640005907@broadcast' })

      expect { post_incoming(conversation, 'promoção') }.not_to change(Message, :count)
    end
  end

  context 'com um contato comum' do
    let(:contact) do
      create(:contact, account: account, phone_number: '+5566999991234',
                       custom_attributes: { 'waha_whatsapp_chat_id' => '5566999991234@c.us' })
    end
    let!(:conversation) { conversation_for(contact) }

    it 'segue criando a mensagem' do
      expect { post_incoming(conversation, 'Bom dia') }.to change(conversation.messages, :count).by(1)
    end
  end
end
