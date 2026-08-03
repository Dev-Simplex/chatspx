# frozen_string_literal: true

require 'rails_helper'

# Kanban tempo real (Fase 4) — criar/renomear/recolorir/reordenar/apagar coluna
# só chegava no colega com F5. Pior: se A apagava a coluna e B arrastava um card
# para ela, B tomava 404 sem explicação.
RSpec.describe 'Funnel Stages realtime', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let!(:stage) { FunnelStage.create!(funnel: funnel, name: 'Abertos', position: 0) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_stages" }

  before { allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original }

  def expect_stages_changed(times: 1)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::FUNNEL_STAGES_CHANGED, anything, hash_including(funnel: funnel))
      .exactly(times).times
  end

  it 'dispara ao criar coluna' do
    post base_url, params: { funnel_stage: { name: 'Em andamento', position: 1 } }, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:created)
    expect_stages_changed
  end

  it 'dispara ao renomear/recolorir coluna' do
    patch "#{base_url}/#{stage.id}", params: { funnel_stage: { name: 'Novos', color: '#ff0000' } }, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:success)
    expect_stages_changed
  end

  it 'dispara ao apagar coluna' do
    delete "#{base_url}/#{stage.id}", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:success)
    expect_stages_changed
  end

  it 'dispara ao reordenar colunas' do
    other = FunnelStage.create!(funnel: funnel, name: 'Fechados', position: 1)

    post "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/reorder_stages",
         params: { stage_ids: [other.id, stage.id] },
         headers: admin.create_new_auth_token

    expect(response).to have_http_status(:success)
    expect_stages_changed
  end

  it 'não dispara quando a criação é rejeitada' do
    post base_url, params: { funnel_stage: { name: '' } }, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      .with(Events::Types::FUNNEL_STAGES_CHANGED, anything, anything)
  end
end
