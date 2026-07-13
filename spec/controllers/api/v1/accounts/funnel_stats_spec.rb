# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel stats (Kanban v2 / Fase 6)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas', team_id: team.id) }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/stats" }

  before { team.add_members([agent.id]) }

  it 'requires authentication' do
    get endpoint
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns live totals, stages and workload' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :open)
    FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: conversation)

    get endpoint, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['totals']['cards']).to eq(1)
    expect(body['stages'].map { |s| s['id'] }).to include(stage.id)
    expect(body).to have_key('workload')
    expect(body).to have_key('baseline')
  end

  it 'exposes yesterday\'s snapshot as the baseline' do
    funnel.funnel_metric_snapshots.create!(
      captured_on: Date.current - 1, metrics: { 'totals' => { 'cards' => 5 } }
    )

    get endpoint, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['baseline']).to eq('cards' => 5)
  end
end
