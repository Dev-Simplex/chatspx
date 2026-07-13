# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel Automations API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas', team_id: team.id) }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aguardando', position: 0) }
  let(:base) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/automations" }

  before { team.add_members([admin.id, agent.id]) }

  describe 'unauthenticated' do
    it 'returns unauthorized' do
      get base
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    let(:payload) do
      {
        funnel_automation: {
          name: 'SLA 24h', funnel_stage_id: stage.id,
          trigger: { event: 'time_in_stage', hours: 24 },
          conditions: [{ field: 'priority', op: 'eq', value: 'high' }],
          actions: [{ type: 'move', stage_id: stage.id }, { type: 'tag', labels: ['atrasado'] }]
        }
      }
    end

    it 'lets an admin create an automation' do
      post base, params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('name' => 'SLA 24h', 'active' => true)
      expect(response.parsed_body['trigger']).to include('event' => 'time_in_stage', 'hours' => 24)
      expect(response.parsed_body['actions'].first).to include('type' => 'move')
      expect(funnel.funnel_automations.count).to eq(1)
    end

    it 'forbids an agent from creating an automation' do
      post base, params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(funnel.funnel_automations.count).to eq(0)
    end

    it 'rejects an unsupported trigger event' do
      bad = payload.deep_dup
      bad[:funnel_automation][:trigger] = { event: 'whenever' }
      post base, params: bad, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET index' do
    it 'lets an agent view configured automations' do
      funnel.funnel_automations.create!(name: 'R', trigger: { 'event' => 'item_entered_stage' })

      get base, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.map { |a| a['name'] }).to include('R')
    end
  end

  describe 'DELETE destroy' do
    it 'lets an admin delete an automation' do
      automation = funnel.funnel_automations.create!(name: 'R', trigger: { 'event' => 'item_entered_stage' })

      delete "#{base}/#{automation.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(funnel.funnel_automations.exists?(automation.id)).to be(false)
    end
  end
end
