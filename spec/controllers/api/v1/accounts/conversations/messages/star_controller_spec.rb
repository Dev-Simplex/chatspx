require 'rails_helper'

RSpec.describe 'Conversation Messages Star API', type: :request do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let!(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation)
  end

  def star_url(msg = message)
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{msg.id}/star"
  end

  describe 'POST /api/v1/accounts/{account_id}/conversations/{id}/messages/{message_id}/star' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post star_url

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an agent with access to the conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: inbox, user: agent)
      end

      it 'stars the message and returns 200 with starred=true' do
        post star_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to include('id' => message.id, 'starred' => true)
        expect(message.reload.starred).to be(true)
      end

      it 'is idempotent — re-starring an already-starred message keeps starred=true' do
        message.update!(starred: true)

        expect do
          post star_url, headers: agent.create_new_auth_token, as: :json
        end.not_to change { message.reload.starred }

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['starred']).to be(true)
      end

      it 'returns 404 for a message that does not exist' do
        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/0/star",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'dispatches MESSAGE_UPDATED when the state actually changes' do
        expect(Rails.configuration.dispatcher).to receive(:dispatch)
          .with(Events::Types::MESSAGE_UPDATED, anything, hash_including(message: instance_of(Message)))

        post star_url, headers: agent.create_new_auth_token, as: :json
      end

      it 'does NOT dispatch MESSAGE_UPDATED when the state is unchanged (idempotent)' do
        message.update!(starred: true)

        expect(Rails.configuration.dispatcher).not_to receive(:dispatch)

        post star_url, headers: agent.create_new_auth_token, as: :json
      end
    end

    context 'when authenticated but without access to the conversation' do
      let(:other_account) { create(:account) }
      let(:outsider) { create(:user, account: other_account, role: :agent) }

      it 'returns 404 (conversation lookup is account-scoped)' do
        post star_url, headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account_id}/conversations/{id}/messages/{message_id}/star' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete star_url

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an agent with access to the conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: inbox, user: agent)
        message.update!(starred: true)
      end

      it 'unstars the message and returns 200 with starred=false' do
        delete star_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to include('id' => message.id, 'starred' => false)
        expect(message.reload.starred).to be(false)
      end

      it 'is idempotent — un-starring an already-unstarred message keeps starred=false' do
        message.update!(starred: false)

        expect do
          delete star_url, headers: agent.create_new_auth_token, as: :json
        end.not_to change { message.reload.starred }

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['starred']).to be(false)
      end

      it 'returns 404 for a message that does not exist' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/0/star",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account_id}/conversations/{id}/messages?starred=true' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:starred_message) do
      create(:message, account: account, inbox: inbox, conversation: conversation, starred: true)
    end
    let!(:other_starred_message) do
      create(:message, account: account, inbox: inbox, conversation: conversation, starred: true)
    end

    before do
      create(:inbox_member, inbox: inbox, user: agent)
    end

    it 'returns only starred messages when starred=true' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages?starred=true",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload_ids = response.parsed_body['payload'].map { |m| m['id'] }
      expect(payload_ids).to contain_exactly(starred_message.id, other_starred_message.id)
      expect(payload_ids).not_to include(message.id) # message is not starred
    end

    it 'returns all messages when starred is absent' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload_ids = response.parsed_body['payload'].map { |m| m['id'] }
      expect(payload_ids).to include(message.id, starred_message.id, other_starred_message.id)
    end

    it 'ignores starred=false (filter is opt-in for starred-only)' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages?starred=false",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload_ids = response.parsed_body['payload'].map { |m| m['id'] }
      # starred=false is a no-op — returns all messages, same as when starred is absent.
      # If a future use case needs "only unstarred", introduce an explicit unstarred filter.
      expect(payload_ids).to include(message.id, starred_message.id, other_starred_message.id)
    end
  end
end
