require 'rails_helper'

RSpec.describe 'Takeover Requests API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:requester) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open) }

  before do
    create(:inbox_member, user: owner, inbox: inbox)
    create(:inbox_member, user: requester, inbox: inbox)
  end

  describe 'POST create (conversation-scoped)' do
    it 'requires authentication' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/takeover_requests"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates a pending request snapshotting the owner' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/takeover_requests",
           params: { reason: 'preciso falar com o cliente' }, headers: requester.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['status']).to eq('pending')
      expect(body['owner']['id']).to eq(owner.id)
      expect(body['requester']['id']).to eq(requester.id)
      expect(ConversationTakeoverRequest.last.owner_id).to eq(owner.id)
    end

    it 'notifies the owner' do
      expect do
        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/takeover_requests",
             headers: requester.create_new_auth_token, as: :json
      end.to change { Notification.where(user_id: owner.id, notification_type: 'conversation_takeover_requested').count }.by(1)
    end

    it 'returns 422 with an error_code for a conversation with no owner' do
      unowned = create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open)
      post "/api/v1/accounts/#{account.id}/conversations/#{unowned.display_id}/takeover_requests",
           headers: requester.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('conversation_unassigned')
    end

    it 'forbids an admin from creating a request (they assign directly)' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/takeover_requests",
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end

  describe 'POST approve/deny/cancel (account-scoped)' do
    let!(:request_record) do
      Conversations::TakeoverRequestService.new(conversation: conversation, actor: requester).create!
    end

    it 'lets the owner approve and transfers the conversation' do
      post "/api/v1/accounts/#{account.id}/takeover_requests/#{request_record.id}/approve",
           headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.assignee_id).to eq(requester.id)
      expect(request_record.reload).to be_approved
    end

    it 'notifies the requester on approve' do
      expect do
        post "/api/v1/accounts/#{account.id}/takeover_requests/#{request_record.id}/approve",
             headers: owner.create_new_auth_token, as: :json
      end.to change {
        Notification.where(user_id: requester.id, notification_type: 'conversation_takeover_responded').count
      }.by(1)
    end

    it 'forbids a bystander agent from approving' do
      bystander = create(:user, account: account, role: :agent)
      post "/api/v1/accounts/#{account.id}/takeover_requests/#{request_record.id}/approve",
           headers: bystander.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      expect(conversation.reload.assignee_id).to eq(owner.id)
    end

    it 'lets an admin force approval' do
      post "/api/v1/accounts/#{account.id}/takeover_requests/#{request_record.id}/approve",
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(conversation.reload.assignee_id).to eq(requester.id)
    end

    it 'lets the owner deny without transferring' do
      post "/api/v1/accounts/#{account.id}/takeover_requests/#{request_record.id}/deny",
           headers: owner.create_new_auth_token, as: :json

      expect(request_record.reload).to be_denied
      expect(conversation.reload.assignee_id).to eq(owner.id)
    end

    it 'lets the requester cancel their own request' do
      post "/api/v1/accounts/#{account.id}/takeover_requests/#{request_record.id}/cancel",
           headers: requester.create_new_auth_token, as: :json
      expect(request_record.reload).to be_cancelled
    end

    it 'returns 422 when approving an already-closed request' do
      Conversations::TakeoverRequestService.new(request: request_record, actor: owner).deny!
      post "/api/v1/accounts/#{account.id}/takeover_requests/#{request_record.id}/approve",
           headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('takeover_request_closed')
    end
  end

  describe 'GET index' do
    it 'shows the owner their incoming requests and hides unrelated ones' do
      mine = Conversations::TakeoverRequestService.new(conversation: conversation, actor: requester).create!
      other_conv = create(:conversation, account: account, inbox: inbox, assignee: requester, status: :open)
      create(:inbox_member, user: create(:user, account: account, role: :agent), inbox: inbox)
      Conversations::TakeoverRequestService.new(
        conversation: other_conv, actor: create(:user, account: account, role: :agent)
      ).create!

      get "/api/v1/accounts/#{account.id}/takeover_requests",
          params: { scope: 'incoming', status: 'pending' }, headers: owner.create_new_auth_token, as: :json

      ids = response.parsed_body['payload'].pluck('id')
      expect(ids).to include(mine.id)
      expect(response.parsed_body['payload'].length).to eq(1)
    end
  end
end
