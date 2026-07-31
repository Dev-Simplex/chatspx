require 'rails_helper'

RSpec.describe 'Team Members API', type: :request do
  let(:account) { create(:account) }
  let(:account_2) { create(:account) }
  let!(:team) { create(:team, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/teams/{team_id}/team_members' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns all the teams' do
        create(:team_member, team: team, user: agent)
        get "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.first['id']).to eq(agent.id)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/teams/{team_id}/team_members' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unathorized for agent' do
        params = { user_id: agent.id }

        post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'add a new team members when its administrator' do
        user_ids = (1..5).map { create(:user, account: account, role: :agent).id }
        params = { user_ids: user_ids }
        # have a team member added already
        create(:team_member, team: team, user: User.find(user_ids.first))

        post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
             params: params,
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.count).to eq(user_ids.count - 1)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/teams/{team_id}/team_members' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'return unauthorized for agent' do
        params = { user_id: agent.id }
        delete "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'destroys the team members when its administrator' do
        user_ids = (1..5).map { create(:user, account: account, role: :agent).id }
        user_ids.each { |id| create(:team_member, team: team, user: User.find(id)) }
        params = { user_ids: user_ids.first(3) }

        delete "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
               params: params,
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(team.team_members.count).to eq(2)
      end
    end
  end

  # T1: o supervisor compõe os times que supervisiona, mas só com gente que já está em
  # algum time supervisionado (o pool). Tirar do time não tem restrição de pool.
  describe 'quando quem chama é supervisor de time' do
    let!(:other_team) { create(:team, account: account) }
    let!(:unsupervised_team) { create(:team, account: account) }
    let!(:supervisor) { create(:user, account: account, role: :agent) }
    let!(:pool_agent) { create(:user, account: account, role: :agent) }
    let!(:outsider) { create(:user, account: account, role: :agent) }

    before do
      # o pool nasce do OUTRO time supervisionado: pool_agent pode migrar para `team`
      create(:team_member, team: other_team, user: pool_agent)
      create(:team_member, team: unsupervised_team, user: outsider)
      create(:team_supervisor, team: team, user: supervisor)
      create(:team_supervisor, team: other_team, user: supervisor)
    end

    it 'adds a member of the pool to a supervised team' do
      post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
           params: { user_ids: [pool_agent.id] },
           headers: supervisor.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(team.reload.members).to contain_exactly(pool_agent)
    end

    it 'refuses to add somebody from outside the pool' do
      post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
           params: { user_ids: [outsider.id] },
           headers: supervisor.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(team.reload.members).to be_empty
    end

    it 'refuses the whole request when a single id is outside the pool' do
      post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
           params: { user_ids: [pool_agent.id, outsider.id] },
           headers: supervisor.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(team.reload.members).to be_empty
    end

    it 'refuses to add himself to a supervised team when he is not in the pool' do
      post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
           params: { user_ids: [supervisor.id] },
           headers: supervisor.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(team.reload.members).to be_empty
    end

    it 'refuses any change on a team he does not supervise' do
      post "/api/v1/accounts/#{account.id}/teams/#{unsupervised_team.id}/team_members",
           params: { user_ids: [pool_agent.id] },
           headers: supervisor.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(unsupervised_team.reload.members).to contain_exactly(outsider)
    end

    it 'removes a member of a supervised team without the pool restriction' do
      create(:team_member, team: team, user: pool_agent)

      delete "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
             params: { user_ids: [pool_agent.id] },
             headers: supervisor.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:success)
      expect(team.reload.members).to be_empty
    end

    it 'refuses a removal on a team he does not supervise' do
      delete "/api/v1/accounts/#{account.id}/teams/#{unsupervised_team.id}/team_members",
             params: { user_ids: [outsider.id] },
             headers: supervisor.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(unsupervised_team.reload.members).to contain_exactly(outsider)
    end

    it 'updates the whole set with the pool on the way in' do
      leaving = create(:user, account: account, role: :agent)
      create(:team_member, team: team, user: leaving)

      patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
            params: { user_ids: [pool_agent.id] },
            headers: supervisor.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(team.reload.members).to contain_exactly(pool_agent)
    end

    it 'refuses an update that brings somebody from outside the pool' do
      patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
            params: { user_ids: [outsider.id] },
            headers: supervisor.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(team.reload.members).to be_empty
    end

    it 'lets him keep the members already in the team (id repetido não é adição)' do
      create(:team_member, team: team, user: outsider)

      patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
            params: { user_ids: [outsider.id, pool_agent.id] },
            headers: supervisor.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(team.reload.members).to contain_exactly(outsider, pool_agent)
    end

    # T4: o pool vem do banco como Integer e o corpo pode chegar como String
    # (form-encoded) — sem a normalização a subtração não casaria e o id de fora
    # passaria batido.
    it 'refuses an id outside the pool sent as a STRING (form-encoded)' do
      post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
           params: { user_ids: [outsider.id.to_s] },
           headers: supervisor.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
      expect(team.reload.members).to be_empty
    end

    it 'refuses a user from ANOTHER account' do
      foreigner = create(:user, account: create(:account), role: :agent)

      post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
           params: { user_ids: [foreigner.id] },
           headers: supervisor.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(team.reload.members).to be_empty
    end

    it 'refuses to add himself to a team he does not supervise' do
      post "/api/v1/accounts/#{account.id}/teams/#{unsupervised_team.id}/team_members",
           params: { user_ids: [supervisor.id] },
           headers: supervisor.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(unsupervised_team.reload.members).to contain_exactly(outsider)
    end

    it 'keeps the agent that supervises nothing out (comportamento atual)' do
      plain_agent = create(:user, account: account, role: :agent)

      post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
           params: { user_ids: [pool_agent.id] },
           headers: plain_agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(team.reload.members).to be_empty
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/teams/{team_id}/team_members' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:agent_2) { create(:user, account: account_2, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'return unauthorized for agent' do
        params = { user_id: agent.id }
        patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
              params: params,
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates the team members when its administrator' do
        user_ids = (1..5).map { create(:user, account: account, role: :agent).id }
        params = { user_ids: user_ids }

        patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
              params: params,
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.count).to eq(user_ids.count)
      end

      it 'ignores the user ids when its not a valid account user id' do
        params = { user_ids: [agent_2.id] }

        patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
              params: params,
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
        json_response = response.parsed_body
        expect(json_response['error']).to eq('Invalid User IDs')
      end
    end
  end
end
