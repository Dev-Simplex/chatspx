require 'rails_helper'

RSpec.describe 'Attachment Bulk Downloads API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:foreign_inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  # cria um attachment real (com blob) numa conversa/inbox
  def create_attachment(target_inbox, file_type: :image, asset: 'sample.png', content_type: 'image/png')
    conversation = create(:conversation, account: account, inbox: target_inbox)
    message = create(:message, account: account, conversation: conversation, inbox: target_inbox)
    attachment = message.attachments.new(account_id: account.id, file_type: file_type)
    attachment.file.attach(io: Rails.root.join("spec/assets/#{asset}").open, filename: asset, content_type: content_type)
    attachment.save!
    [attachment, conversation]
  end

  describe 'POST /api/v1/accounts/{account.id}/attachment_bulk_downloads' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads", params: { attachment_ids: [1] }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with attachment_ids in the agent visible scope' do
      it 'returns 202 with a pending record and enqueues the job' do
        attachment, = create_attachment(inbox)

        expect do
          post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
               headers: agent.create_new_auth_token, params: { attachment_ids: [attachment.id] }, as: :json
        end.to have_enqueued_job(Attachments::BulkDownloadJob)

        expect(response).to have_http_status(:accepted)
        body = response.parsed_body
        expect(body['status']).to eq('pending')
        expect(body['total_count']).to eq(1)
        expect(AttachmentBulkDownload.last.audit_meta).to include('origin' => 'gallery')
      end
    end

    context 'with the filters / select-all mode' do
      it 'returns 202 scoping to what the gallery shows' do
        create_attachment(inbox)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { filters: { type: 'image' } }, as: :json

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body['total_count']).to eq(1)
      end
    end

    context 'with attachments outside the agent scope' do
      it 'silently drops ids from an inbox the agent is not assigned to' do
        foreign_attachment, = create_attachment(foreign_inbox)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { attachment_ids: [foreign_attachment.id] }, as: :json

        # nada baixável -> 422, nunca um zip com mídia de inbox alheia
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('nothing_to_download')
      end

      it 'counts only the visible attachments when ids are mixed' do
        own_attachment, = create_attachment(inbox)
        foreign_attachment, = create_attachment(foreign_inbox)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token,
             params: { attachment_ids: [own_attachment.id, foreign_attachment.id] }, as: :json

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body['total_count']).to eq(1)
      end
    end

    context 'when hitting caps or anti-abuse limits' do
      it 'rejects too many files' do
        attachment, = create_attachment(inbox)
        stub_const('AttachmentBulkDownload::MAX_FILES', 0)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { attachment_ids: [attachment.id] }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('too_many_files')
      end

      it 'rejects a selection over the byte cap' do
        attachment, = create_attachment(inbox)
        stub_const('AttachmentBulkDownload::MAX_TOTAL_BYTES', 1)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { attachment_ids: [attachment.id] }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('too_large')
      end

      it 'rejects a second active export from the same user' do
        attachment, = create_attachment(inbox)
        create(:attachment_bulk_download, account: account, requester_user: agent, status: :processing)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { attachment_ids: [attachment.id] }, as: :json

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body['error']).to eq('export_active')
      end
    end

    context 'when in conversation mode' do
      it 'allows an agent assigned to the conversation inbox' do
        _attachment, conversation = create_attachment(inbox)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { conversation_id: conversation.display_id }, as: :json

        expect(response).to have_http_status(:accepted)
        expect(AttachmentBulkDownload.last.audit_meta).to include('origin' => 'conversation')
      end

      it 'forbids an agent not assigned to the conversation inbox' do
        _attachment, conversation = create_attachment(foreign_inbox)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { conversation_id: conversation.display_id }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'forbids a member when the conversation is isolated to another agent' do
        _attachment, conversation = create_attachment(inbox)
        create(:inbox_member, user: other_agent, inbox: inbox)
        inbox.update!(agent_conversation_isolation: true)
        # COM time: o isolamento e escopado pelo time da conversa
        # (Inbox#isolation_applies_to_team?), e o dono precisa ser membro do time
        # senao o AssignmentHandler zera o assignee ao carimbar o time.
        iso_team = create(:team, account: account, allow_auto_assign: false)
        create(:team_member, team: iso_team, user: other_agent)
        conversation.update!(team: iso_team, assignee: other_agent)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { conversation_id: conversation.display_id }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      # CONVERSA SEM TIME (antes da triagem): esta regra NAO e isenta do time nulo (fica
      # fora de Inbox::TEAMLESS_EXEMPT_RULES), entao o download em massa continua negado.
      # Baixar a midia da conversa do colega e o mesmo vazamento da tela, so que em ZIP.
      it 'STILL forbids the download when the isolated conversation has no team yet' do
        _attachment, conversation = create_attachment(inbox)
        create(:inbox_member, user: other_agent, inbox: inbox)
        inbox.update!(agent_conversation_isolation: true)
        conversation.update!(team: nil, assignee: other_agent)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { conversation_id: conversation.display_id }, as: :json

        expect(conversation.reload.team_id).to be_nil
        expect(response).to have_http_status(:unauthorized)
      end

      it 'still allows the assigned agent when the conversation is isolated' do
        _attachment, conversation = create_attachment(inbox)
        inbox.update!(agent_conversation_isolation: true)
        conversation.update!(assignee: agent)

        post "/api/v1/accounts/#{account.id}/attachment_bulk_downloads",
             headers: agent.create_new_auth_token, params: { conversation_id: conversation.display_id }, as: :json

        expect(response).to have_http_status(:accepted)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/attachment_bulk_downloads/{id}' do
    let(:export) { create(:attachment_bulk_download, account: account, requester_user: agent, status: :processing) }

    it 'returns the record to its requester' do
      get "/api/v1/accounts/#{account.id}/attachment_bulk_downloads/#{export.id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('processing')
    end

    it 'does not let another agent read it' do
      get "/api/v1/accounts/#{account.id}/attachment_bulk_downloads/#{export.id}",
          headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
