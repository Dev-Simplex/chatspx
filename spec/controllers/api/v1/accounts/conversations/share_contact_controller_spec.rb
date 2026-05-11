require 'rails_helper'

RSpec.describe 'Conversation Share Contact API', type: :request do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, name: 'Sender Agent', account: account, role: :agent) }
  let!(:other_agent) { create(:user, name: 'Other Agent', account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  def share_contact_url
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/share_contact"
  end

  describe 'POST share_contact' do
    context 'when source is manual' do
      it 'creates an outgoing message with a contact attachment' do
        post share_contact_url,
             params: { source: 'manual', name: 'Joana Cliente', phone: '5511999998888' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        message = conversation.messages.last
        expect(message).to be_present
        expect(message.message_type).to eq('outgoing')
        expect(message.attachments.first.file_type).to eq('contact')
        expect(message.attachments.first.fallback_title).to eq('+5511999998888')
        expect(message.additional_attributes['contact']).to include('source' => 'manual', 'name' => 'Joana Cliente')
      end
    end

    context 'when source is contact' do
      let!(:saved_contact) do
        create(:contact, account: account, name: 'Cliente Salvo', phone_number: '+5511988887777')
      end

      it 'pulls name/phone from the saved contact' do
        post share_contact_url,
             params: { source: 'contact', contact_id: saved_contact.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        message = conversation.messages.last
        expect(message.attachments.first.file_type).to eq('contact')
        expect(message.attachments.first.fallback_title).to eq('+5511988887777')
        expect(message.additional_attributes['contact']).to include('source' => 'contact', 'name' => 'Cliente Salvo')
      end
    end

    context 'when source is agent' do
      it 'persists the agent name and phone provided by the client' do
        post share_contact_url,
             params: { source: 'agent', agent_id: other_agent.id, phone: '5511977776666' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        message = conversation.messages.last
        expect(message.attachments.first.file_type).to eq('contact')
        expect(message.attachments.first.fallback_title).to eq('+5511977776666')
        expect(message.additional_attributes['contact']).to include('source' => 'agent', 'name' => other_agent.name)
      end
    end

    context 'when source is invalid' do
      it 'returns an error' do
        post share_contact_url,
             params: { source: 'unknown', name: 'X', phone: '+5511' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
