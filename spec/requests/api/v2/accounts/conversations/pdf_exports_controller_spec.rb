require 'rails_helper'

# O PDF é a transcrição inteira da conversa, com notas privadas. Ser membro da caixa não basta:
# vale a mesma trava de time e de isolamento por agente de GET /conversations/:id.
RSpec.describe 'Conversation PDF exports access', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:params) { { pdf_export: { include_private: true } } }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def exports_url(conversation, id = nil)
    ["/api/v2/accounts/#{account.id}/conversations/#{conversation.display_id}/pdf_exports", id].compact.join('/')
  end

  context 'when the conversation belongs to a team the agent is not in' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, team: create(:team, account: account)) }

    it 'refuses to create the export' do
      expect do
        post exports_url(conversation), headers: agent.create_new_auth_token, params: params, as: :json
      end.not_to have_enqueued_job(Conversations::ExportPdfJob)

      expect(response).to have_http_status(:forbidden)
      expect(ConversationPdfExport.count).to eq(0)
    end

    it 'refuses to show an existing export' do
      export = ConversationPdfExport.create!(conversation: conversation, account: account, filters: { include_private: true })

      get exports_url(conversation, export.id), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'when the inbox isolates conversations per agent and a colleague owns it' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: create(:user, account: account, role: :agent)) }

    before { inbox.update!(agent_conversation_isolation: true) }

    it 'refuses to create the export' do
      post exports_url(conversation), headers: agent.create_new_auth_token, params: params, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error_code']).to eq('conversation_access_blocked')
    end
  end

  context 'when the agent owns the conversation' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

    it 'still creates the export' do
      expect do
        post exports_url(conversation), headers: agent.create_new_auth_token, params: params, as: :json
      end.to have_enqueued_job(Conversations::ExportPdfJob)

      expect(response).to have_http_status(:accepted)
    end
  end
end
