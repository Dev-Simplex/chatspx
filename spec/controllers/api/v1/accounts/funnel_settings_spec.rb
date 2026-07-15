# frozen_string_literal: true

require 'rails_helper'

# Kanban v2 (Fase 1) — funnels/funnel_stages expose and persist a `settings`
# jsonb (WIP limit, SLA hours, deadline mode) without disturbing the legacy
# attributes.
RSpec.describe 'Funnel settings (Kanban v2)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Time X', color: '#94a3b8', team_id: team.id) }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Abertos', position: 0) }

  before { team.add_members([agent.id]) }

  describe 'PATCH /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_stages/:id' do
    it 'persists wip_limit and sla_hours in settings and serializes them back' do
      patch "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_stages/#{stage.id}",
            params: { funnel_stage: { settings: { wip_limit: 5, sla_hours: 24 } } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['settings']).to include('wip_limit' => 5, 'sla_hours' => 24)
      expect(stage.reload.settings).to include('wip_limit' => 5, 'sla_hours' => 24)
      expect(stage.wip_limit).to eq(5)
    end

    it 'does not clobber a sibling settings key when only one is sent' do
      stage.update!(settings: { 'wip_limit' => 3, 'sla_hours' => 12 })

      patch "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_stages/#{stage.id}",
            params: { funnel_stage: { settings: { wip_limit: 3, sla_hours: 48 } } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload.settings).to include('wip_limit' => 3, 'sla_hours' => 48)
    end

    it 'ignores unpermitted settings keys' do
      patch "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_stages/#{stage.id}",
            params: { funnel_stage: { settings: { wip_limit: 2, evil: 'x' } } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload.settings).to eq('wip_limit' => 2)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/funnels/:id' do
    it 'persists deadline_mode in funnel settings and serializes it back' do
      patch "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}",
            params: { funnel: { settings: { deadline_mode: true } } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['settings']).to include('deadline_mode' => true)
      expect(funnel.reload.settings).to include('deadline_mode' => true)
    end
  end

  describe 'GET funnel_stages index' do
    it 'includes settings (defaulting to {}) for each stage' do
      stage
      get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_stages",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      stage_payload = response.parsed_body.find { |s| s['id'] == stage.id }
      expect(stage_payload).to have_key('settings')
      expect(stage_payload['settings']).to eq({})
    end
  end
end
