require 'rails_helper'

RSpec.describe 'Conversation UserSettings API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
    create(:inbox_member, inbox: conversation.inbox, user: other_agent)
  end

  describe 'PATCH /api/v1/accounts/:account_id/conversations/:conversation_id/user_setting' do
    let(:url) do
      "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/user_setting"
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch url, params: { user_setting: { pinned: true } }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'sets pinned=true for the current user only' do
        patch url,
              params: { user_setting: { pinned: true } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['user_id']).to eq(agent.id)
        expect(body['user_settings']['pinned']).to be(true)

        conversation.reload
        expect(conversation.user_setting_for(agent.id)['pinned']).to be(true)
        expect(conversation.user_setting_for(other_agent.id)).to eq({})
      end

      it 'accepts ISO8601 archived_at' do
        timestamp = '2026-05-14T12:34:56Z'
        patch url,
              params: { user_setting: { archived_at: timestamp } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['user_settings']['archived_at']).to eq(timestamp)
      end

      it 'accepts ISO8601 muted_until' do
        timestamp = '2026-12-31T23:59:59Z'
        patch url,
              params: { user_setting: { muted_until: timestamp } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['user_settings']['muted_until']).to eq(timestamp)
      end

      it 'rejects invalid ISO8601 strings' do
        patch url,
              params: { user_setting: { archived_at: 'not-a-date' } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('archived_at')
      end

      it 'rejects non-boolean pinned' do
        patch url,
              params: { user_setting: { pinned: 'yes' } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'merges multiple keys without dropping previous values' do
        patch url,
              params: { user_setting: { pinned: true } },
              headers: agent.create_new_auth_token,
              as: :json

        patch url,
              params: { user_setting: { archived_at: '2026-06-01T00:00:00Z' } },
              headers: agent.create_new_auth_token,
              as: :json

        conversation.reload
        settings = conversation.user_setting_for(agent.id)
        expect(settings['pinned']).to be(true)
        expect(settings['archived_at']).to eq('2026-06-01T00:00:00Z')
      end

      it 'isolates settings between users (user A cannot see/affect user B)' do
        patch url,
              params: { user_setting: { pinned: true } },
              headers: agent.create_new_auth_token,
              as: :json

        patch url,
              params: { user_setting: { pinned: false } },
              headers: other_agent.create_new_auth_token,
              as: :json

        conversation.reload
        expect(conversation.user_setting_for(agent.id)['pinned']).to be(true)
        expect(conversation.user_setting_for(other_agent.id)['pinned']).to be(false)
      end

      it 'rejects empty patch' do
        patch url,
              params: { user_setting: {} },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/conversations/:conversation_id/user_setting' do
    let(:url) do
      "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/user_setting"
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete url, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      before do
        Conversations::UserSettingUpdateService.new(
          conversation: conversation,
          user_id: agent.id,
          patch: { pinned: true, archived_at: '2026-05-14T12:00:00Z' }
        ).perform
        Conversations::UserSettingUpdateService.new(
          conversation: conversation,
          user_id: other_agent.id,
          patch: { pinned: true }
        ).perform
      end

      it 'removes only the current user node, preserving other users' do
        delete url,
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:no_content)

        conversation.reload
        expect(conversation.user_setting_for(agent.id)).to eq({})
        expect(conversation.user_setting_for(other_agent.id)['pinned']).to be(true)
      end
    end
  end
end
