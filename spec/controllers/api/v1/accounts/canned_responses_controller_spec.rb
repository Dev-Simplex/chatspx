require 'rails_helper'

RSpec.describe 'Canned Responses API', type: :request do
  let(:account) { create(:account) }

  before do
    create(:canned_response, account: account, content: 'Hey {{ contact.name }}, Thanks for reaching out', short_code: 'name-short-code')
  end

  describe 'GET /api/v1/accounts/{account.id}/canned_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/canned_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns all the canned responses with the visibility fields' do
        get "/api/v1/accounts/#{account.id}/canned_responses",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.length).to eq(1)
        expect(body.first).to include(
          'short_code' => 'name-short-code',
          'visibility' => 'everyone',
          'team_id' => nil,
          'created_by' => nil,
          'attachments' => []
        )
      end

      it 'returns all the canned responses the user searched for' do
        cr1 = account.canned_responses.first
        create(:canned_response, account: account, content: 'Great! Looking forward', short_code: 'short-code')
        cr2 = create(:canned_response, account: account, content: 'Thanks for reaching out', short_code: 'content-with-thanks')
        cr3 = create(:canned_response, account: account, content: 'Thanks for reaching out', short_code: 'Thanks')

        params = { search: 'thanks' }

        get "/api/v1/accounts/#{account.id}/canned_responses",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.pluck('id')).to eq([cr3, cr2, cr1].map(&:id))
      end
    end

    context 'when filtering by visibility' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let(:agent_1) { create(:user, account: account, role: :agent) }
      let(:agent_2) { create(:user, account: account, role: :agent) }
      let(:team_1) { create(:team, account: account) }
      let(:team_2) { create(:team, account: account) }

      before do
        create(:canned_response, account: account, visibility: :personal, created_by: agent_1, short_code: 'a1-private')
        create(:canned_response, account: account, visibility: :personal, created_by: agent_2, short_code: 'a2-private')
        create(:canned_response, account: account, visibility: :team, team: team_1, created_by: admin, short_code: 't1-cr')
        create(:canned_response, account: account, visibility: :team, team: team_2, created_by: admin, short_code: 't2-cr')
        create(:team_member, user: agent_1, team: team_1)
      end

      it 'shows every response to an administrator' do
        get "/api/v1/accounts/#{account.id}/canned_responses",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body.pluck('short_code')).to include('a1-private', 'a2-private', 't1-cr', 't2-cr')
      end

      it 'scopes the catalog to what the agent may see' do
        get "/api/v1/accounts/#{account.id}/canned_responses",
            headers: agent_1.create_new_auth_token, as: :json

        codes = response.parsed_body.pluck('short_code')
        expect(codes).to include('name-short-code', 'a1-private', 't1-cr')
        expect(codes).not_to include('a2-private', 't2-cr')
      end

      it 'keeps the visibility scope when searching (compositor endpoint)' do
        get "/api/v1/accounts/#{account.id}/canned_responses",
            params: { search: 'Content' }, headers: agent_1.create_new_auth_token, as: :json

        codes = response.parsed_body.pluck('short_code')
        expect(codes).to include('a1-private', 't1-cr')
        expect(codes).not_to include('a2-private', 't2-cr')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/canned_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/canned_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:admin) { create(:user, account: account, role: :administrator) }
      let(:team) { create(:team, account: account) }

      it 'creates a public canned response by default and sets created_by' do
        params = { canned_response: { short_code: 'short', content: 'content' } }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.canned_responses.count).to eq(2)
        created = account.canned_responses.find_by(short_code: 'short')
        expect(created.visibility).to eq('everyone')
        expect(created.created_by_id).to eq(agent.id)
      end

      it 'creates a private canned response' do
        params = { canned_response: { short_code: 'mine', content: 'content', visibility: 'personal' } }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.canned_responses.find_by(short_code: 'mine').visibility).to eq('personal')
      end

      it 'allows a team member to create a team canned response' do
        create(:team_member, user: agent, team: team)
        params = { canned_response: { short_code: 'team-cr', content: 'content', visibility: 'team', team_id: team.id } }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.canned_responses.find_by(short_code: 'team-cr').team_id).to eq(team.id)
      end

      it 'forbids a non-member agent from creating a team canned response' do
        params = { canned_response: { short_code: 'team-cr', content: 'content', visibility: 'team', team_id: team.id } }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(account.canned_responses.find_by(short_code: 'team-cr')).to be_nil
      end

      it 'allows an admin to create a team canned response for any team' do
        params = { canned_response: { short_code: 'team-cr', content: 'content', visibility: 'team', team_id: team.id } }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/canned_responses/:id' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:author) { create(:user, account: account, role: :agent) }
    let(:other_agent) { create(:user, account: account, role: :agent) }
    let(:team) { create(:team, account: account) }

    context 'when it is an unauthenticated user' do
      let(:canned_response) { account.canned_responses.first }

      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'lets any agent edit the content of a public response (permissive model)' do
      public_cr = create(:canned_response, account: account, visibility: :everyone, created_by: author, short_code: 'pub')

      put "/api/v1/accounts/#{account.id}/canned_responses/#{public_cr.id}",
          params: { canned_response: { content: 'edited' } }, headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(public_cr.reload.content).to eq('edited')
    end

    it 'lets any agent edit a legacy orphan public response' do
      legacy = account.canned_responses.first # created_by nil, everyone

      put "/api/v1/accounts/#{account.id}/canned_responses/#{legacy.id}",
          params: { canned_response: { content: 'edited' } }, headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'lets the author edit their own private response' do
      private_cr = create(:canned_response, account: account, visibility: :personal, created_by: author, short_code: 'priv')

      put "/api/v1/accounts/#{account.id}/canned_responses/#{private_cr.id}",
          params: { canned_response: { content: 'edited' } }, headers: author.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'forbids a non-author from editing a private response of another user' do
      private_cr = create(:canned_response, account: account, visibility: :personal, created_by: author, short_code: 'priv')

      put "/api/v1/accounts/#{account.id}/canned_responses/#{private_cr.id}",
          params: { canned_response: { content: 'edited' } }, headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lets a team member edit a team response' do
      create(:team_member, user: other_agent, team: team)
      team_cr = create(:canned_response, account: account, visibility: :team, team: team, created_by: author, short_code: 'tm')

      put "/api/v1/accounts/#{account.id}/canned_responses/#{team_cr.id}",
          params: { canned_response: { content: 'edited' } }, headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'forbids a non-member from editing a team response' do
      team_cr = create(:canned_response, account: account, visibility: :team, team: team, created_by: author, short_code: 'tm')

      put "/api/v1/accounts/#{account.id}/canned_responses/#{team_cr.id}",
          params: { canned_response: { content: 'edited' } }, headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when changing the visibility of a public response' do
      it 'forbids a non-author from converting a public response to private' do
        public_cr = create(:canned_response, account: account, visibility: :everyone, created_by: author, short_code: 'pub')

        put "/api/v1/accounts/#{account.id}/canned_responses/#{public_cr.id}",
            params: { canned_response: { visibility: 'personal' } }, headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(public_cr.reload.visibility).to eq('everyone')
      end

      it 'lets the author convert their own public response to private' do
        public_cr = create(:canned_response, account: account, visibility: :everyone, created_by: author, short_code: 'pub')

        put "/api/v1/accounts/#{account.id}/canned_responses/#{public_cr.id}",
            params: { canned_response: { visibility: 'personal' } }, headers: author.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(public_cr.reload.visibility).to eq('personal')
      end

      it 'lets an admin re-scope a legacy orphan public response' do
        legacy = account.canned_responses.first # orphan, everyone

        put "/api/v1/accounts/#{account.id}/canned_responses/#{legacy.id}",
            params: { canned_response: { visibility: 'personal' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      it 'forbids an agent from re-scoping a legacy orphan public response' do
        legacy = account.canned_responses.first # orphan, everyone

        put "/api/v1/accounts/#{account.id}/canned_responses/#{legacy.id}",
            params: { canned_response: { visibility: 'personal' } }, headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when narrowing a team response to private' do
      before do
        create(:team_member, user: author, team: team)
        create(:team_member, user: other_agent, team: team)
      end

      it 'forbids a non-author team member from converting a team response to private' do
        team_cr = create(:canned_response, account: account, visibility: :team, team: team, created_by: author, short_code: 'tm')

        put "/api/v1/accounts/#{account.id}/canned_responses/#{team_cr.id}",
            params: { canned_response: { visibility: 'personal', team_id: nil } },
            headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(team_cr.reload.visibility).to eq('team')
      end

      it 'lets the author convert their own team response to private' do
        team_cr = create(:canned_response, account: account, visibility: :team, team: team, created_by: author, short_code: 'tm')

        put "/api/v1/accounts/#{account.id}/canned_responses/#{team_cr.id}",
            params: { canned_response: { visibility: 'personal', team_id: nil } },
            headers: author.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(team_cr.reload.visibility).to eq('personal')
      end

      it 'lets any team member widen a team response to public' do
        team_cr = create(:canned_response, account: account, visibility: :team, team: team, created_by: author, short_code: 'tm')

        put "/api/v1/accounts/#{account.id}/canned_responses/#{team_cr.id}",
            params: { canned_response: { visibility: 'everyone', team_id: nil } },
            headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(team_cr.reload.visibility).to eq('everyone')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/canned_responses/:id' do
    let(:author) { create(:user, account: account, role: :agent) }
    let(:other_agent) { create(:user, account: account, role: :agent) }

    context 'when it is an unauthenticated user' do
      let(:canned_response) { account.canned_responses.first }

      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'lets any agent delete a public response' do
      public_cr = create(:canned_response, account: account, visibility: :everyone, created_by: author, short_code: 'pub')

      delete "/api/v1/accounts/#{account.id}/canned_responses/#{public_cr.id}",
             headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(CannedResponse.exists?(public_cr.id)).to be(false)
    end

    it 'forbids a non-author from deleting a private response of another user' do
      private_cr = create(:canned_response, account: account, visibility: :personal, created_by: author, short_code: 'priv')

      delete "/api/v1/accounts/#{account.id}/canned_responses/#{private_cr.id}",
             headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(CannedResponse.exists?(private_cr.id)).to be(true)
    end
  end
end
