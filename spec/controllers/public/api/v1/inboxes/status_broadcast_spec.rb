require 'rails_helper'

# CHAT-170: as atualizações de status do WhatsApp ("stories") chegam da app `chatwoot`
# da WAHA como o chat `status@broadcast`. Não são atendimento: não podem virar
# conversa nem mensagem (cada uma disparava uma execução de LLM no agente de IA).
RSpec.describe 'Public Inbox API — status@broadcast da WAHA', type: :request do
  let!(:api_channel) { create(:channel_api) }
  let(:inbox) { api_channel.inbox }

  let(:status_contact) do
    create(:contact, account: api_channel.account, identifier: 'status@broadcast',
                     custom_attributes: { 'waha_whatsapp_chat_id' => 'status@broadcast' })
  end
  let(:status_contact_inbox) { create(:contact_inbox, contact: status_contact, inbox: inbox) }

  let(:direct_contact) do
    create(:contact, account: api_channel.account, phone_number: '+5566999991234',
                     custom_attributes: { 'waha_whatsapp_chat_id' => '5566999991234@c.us' })
  end
  let(:direct_contact_inbox) { create(:contact_inbox, contact: direct_contact, inbox: inbox) }

  before { inbox.update!(waha_session_name: 'Simplex') }

  def contact_path(contact_inbox)
    "/public/api/v1/inboxes/#{api_channel.identifier}/contacts/#{contact_inbox.source_id}"
  end

  describe 'POST conversations' do
    it 'não cria conversa para status@broadcast' do
      expect { post "#{contact_path(status_contact_inbox)}/conversations" }.not_to change(Conversation, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'não cria conversa quando o sinal vem só no custom_attributes' do
      status_contact.update!(identifier: nil, custom_attributes: { 'waha_whatsapp_jid' => 'status@broadcast' })

      expect { post "#{contact_path(status_contact_inbox)}/conversations" }.not_to change(Conversation, :count)
    end

    it 'segue criando conversa para contato normal' do
      expect { post "#{contact_path(direct_contact_inbox)}/conversations" }.to change(Conversation, :count).by(1)
    end
  end

  describe 'POST messages' do
    # Conversa de status que já existe no banco (a app da WAHA reaproveita o id dela).
    let(:status_conversation) do
      create(:conversation, contact: status_contact, contact_inbox: status_contact_inbox, inbox: inbox)
    end
    let(:direct_conversation) do
      create(:conversation, contact: direct_contact, contact_inbox: direct_contact_inbox, inbox: inbox)
    end

    it 'não cria mensagem para status@broadcast' do
      path = "#{contact_path(status_contact_inbox)}/conversations/#{status_conversation.display_id}/messages"

      expect { post path, params: { content: 'story' } }.not_to change(Message, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'segue criando mensagem para contato normal' do
      path = "#{contact_path(direct_contact_inbox)}/conversations/#{direct_conversation.display_id}/messages"

      expect { post path, params: { content: 'Bom dia' } }.to change(Message, :count).by(1)
    end
  end
end
