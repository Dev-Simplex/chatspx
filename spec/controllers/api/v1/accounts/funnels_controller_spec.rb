# frozen_string_literal: true

require 'rails_helper'

# Covers the "hide the Geral funnel from agents" rule (FunnelPolicy) at the
# controller boundary: agents can no longer list/open/stat/items the account
# default funnel (team_id nil), while admins still can. Also covers the two
# surface guards (funnel_views funnel_id validation + non-admin team_id nil).
RSpec.describe 'Funnels API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  let(:team) { create(:team, account: account) }

  # "Geral" — the account default funnel (team_id nil).
  let!(:general_funnel) { Funnel.create!(account: account, name: 'Geral', color: '#94a3b8', position: 0) }
  let!(:team_funnel) { Funnel.create!(account: account, name: 'Time X', color: '#2563eb', team_id: team.id) }

  before do
    team.add_members([agent.id])
  end

  describe 'GET /api/v1/accounts/:account_id/funnels (index)' do
    it 'requires authentication' do
      get "/api/v1/accounts/#{account.id}/funnels"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'includes the "Geral" default funnel for an administrator' do
      get "/api/v1/accounts/#{account.id}/funnels", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      team_ids = response.parsed_body.map { |f| f['team_id'] }
      expect(team_ids).to include(nil)
    end

    it 'excludes the "Geral" default funnel for an agent (only their team funnels)' do
      get "/api/v1/accounts/#{account.id}/funnels", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.map { |f| f['team_id'] }).not_to include(nil)
      expect(body.map { |f| f['id'] }).to include(team_funnel.id)
      expect(body.map { |f| f['id'] }).not_to include(general_funnel.id)
    end
  end

  describe 'GET show / stats of the "Geral" funnel' do
    it 'returns 404 for an agent (policy_scope does not resolve it)' do
      get "/api/v1/accounts/#{account.id}/funnels/#{general_funnel.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      get "/api/v1/accounts/#{account.id}/funnels/#{general_funnel.id}/stats", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 200 for an administrator' do
      get "/api/v1/accounts/#{account.id}/funnels/#{general_funnel.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET funnel_items of the "Geral" funnel' do
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
    let(:stage) { FunnelStage.create!(funnel: general_funnel, name: 'Aberto', automation_type: 'open', position: 0) }

    it 'returns 404 for an agent' do
      get "/api/v1/accounts/#{account.id}/funnels/#{general_funnel.id}/funnel_items",
          headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 200 for an administrator' do
      stage
      get "/api/v1/accounts/#{account.id}/funnels/#{general_funnel.id}/funnel_items",
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'placement regression (conversation without a team lives only in Geral)' do
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
    let!(:open_stage) { FunnelStage.create!(funnel: general_funnel, name: 'Aberto', automation_type: 'open', position: 0) }

    it 'keeps such items visible to the admin in the Geral funnel and invisible to the agent' do
      conversation = create(:conversation, account: account, inbox: inbox, status: :open, team: nil)
      item = FunnelItem.create!(funnel: general_funnel, funnel_stage: open_stage, conversation: conversation)

      get "/api/v1/accounts/#{account.id}/funnels/#{general_funnel.id}/funnel_items",
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.map { |i| i['id'] }).to include(item.id)

      # the agent can't even reach the Geral funnel's items endpoint
      get "/api/v1/accounts/#{account.id}/funnels/#{general_funnel.id}/funnel_items",
          headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'non-admin cannot create/point a funnel at the Geral bucket (team_id nil)' do
    it 'forbids an agent creating a funnel without a team and explains why' do
      post "/api/v1/accounts/#{account.id}/funnels",
           params: { funnel: { name: 'Meu Funil', color: '#000000' } },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      # the response must carry a human-readable reason (not an empty 403) so the UI can show it
      expect(response.parsed_body['error']).to be_present
    end

    it 'lets an agent create a funnel with a team and then see it' do
      post "/api/v1/accounts/#{account.id}/funnels",
           params: { funnel: { name: 'Funil do Time', color: '#000000', team_id: team.id } },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      created_id = response.parsed_body['id']
      get "/api/v1/accounts/#{account.id}/funnels", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body.map { |f| f['id'] }).to include(created_id)
    end

    it 'forbids an agent clearing a team funnel back to team_id nil' do
      patch "/api/v1/accounts/#{account.id}/funnels/#{team_funnel.id}",
            params: { funnel: { team_id: '' } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids an agent creating a funnel for a team they do not belong to' do
      other_team = create(:team, account: account) # agent is NOT a member
      post "/api/v1/accounts/#{account.id}/funnels",
           params: { funnel: { name: 'Time Alheio', color: '#000000', team_id: other_team.id } },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(account.funnels.exists?(name: 'Time Alheio')).to be(false)
    end

    it 'lets an admin create a funnel without a team' do
      post "/api/v1/accounts/#{account.id}/funnels",
           params: { funnel: { name: 'Geral Admin', color: '#000000' } },
           headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['team_id']).to be_nil
    end
  end

  describe 'funnel_views must reference a visible funnel (surface guard)' do
    it 'returns 404 for an agent listing views of the Geral funnel' do
      get "/api/v1/accounts/#{account.id}/funnel_views?funnel_id=#{general_funnel.id}",
          headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for an agent creating a view of the Geral funnel' do
      post "/api/v1/accounts/#{account.id}/funnel_views",
           params: { funnel_view: { name: 'v', funnel_id: general_funnel.id, view_mode: 'board' } },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'lets an admin list views of the Geral funnel' do
      get "/api/v1/accounts/#{account.id}/funnel_views?funnel_id=#{general_funnel.id}",
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
