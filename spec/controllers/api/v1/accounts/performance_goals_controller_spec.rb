require 'rails_helper'

# CHAT-177: o que cada papel recebe e o que e cortado -- conferido na resposta CRUA da API.
RSpec.describe 'Metas e ranking do time', type: :request do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account, name: 'Vendas') }
  let(:other_team) { create(:team, account: account, name: 'Suporte') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Chefe', display_name: 'Chefe') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana', display_name: 'Ana') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia', display_name: 'Bia') }
  let(:caio) { create(:user, account: account, role: :agent, name: 'Caio', display_name: 'Caio') }
  let(:month) { PerformanceGoals::Month.current(account).strftime('%Y-%m') }
  let(:ranking_url) { "/api/v1/accounts/#{account.id}/performance_ranking" }
  let(:goals_url) { "/api/v1/accounts/#{account.id}/performance_goals" }

  before do
    create(:team_member, team: team, user: ana)
    create(:team_member, team: team, user: bia)
    create(:team_member, team: other_team, user: caio)
    [ana, bia, caio].each do |user|
      PerformanceGoal.create!(account: account, month: Date.current.beginning_of_month, target_type: 'user', target_id: user.id,
                              metric: 'resolved_conversations', value: 10)
    end
  end

  def ranking_as(user, **params)
    get ranking_url, params: { month: month }.merge(params), headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  def visibility!(value)
    account.update!(goals_visibility: value)
  end

  describe 'GET performance_ranking' do
    it 'managers (padrao): atendente leva 403' do
      ranking_as(ana)
      expect(response).to have_http_status(:forbidden)
    end

    it 'own: atendente recebe so o proprio, nenhum dado de colega' do
      visibility!('own')
      body = ranking_as(ana)

      expect(response).to have_http_status(:success)
      expect(body['rows']).to be_empty
      expect(body['without_goal']).to be_empty
      expect(body.dig('me', 'name')).to eq('Ana')
      expect(body.dig('me', 'metrics', 'resolved_conversations', 'goal')).to eq(10.0)
      expect(response.body).not_to include('Bia', 'Caio')
    end

    it 'everyone: colegas do time vem sem actual e sem goal; o proprio completo' do
      visibility!('everyone')
      body = ranking_as(ana)

      bia_row = body['rows'].find { |row| row['name'] == 'Bia' }
      expect(bia_row['metrics'].values).to all(include('actual' => nil, 'goal' => nil))
      expect(bia_row).to include('position', 'overall')
      expect(body['rows'].pluck('name')).not_to include('Caio')
      expect(body.dig('me', 'metrics', 'resolved_conversations', 'goal')).to eq(10.0)
      expect(body['without_goal']).to be_empty
    end

    it 'administrador ve todos com numeros completos e o bloco sem meta' do
      body = ranking_as(admin)

      expect(body['can_manage']).to be(true)
      expect(body['rows'].pluck('name')).to contain_exactly('Ana', 'Bia', 'Caio')
      expect(body['rows'].first.dig('metrics', 'resolved_conversations', 'goal')).to eq(10.0)
      expect(body['without_goal'].pluck('name')).to include('Chefe')
    end

    it 'supervisor de time ve so os atendentes dos times que supervisiona' do
      supervisor = create(:user, account: account, role: :administrator, name: 'Sup', display_name: 'Sup')
      AccountUser.find_by(account: account, user: supervisor).update!(supervised_team_ids: [team.id])

      body = ranking_as(supervisor)
      expect(body['rows'].pluck('name')).to contain_exactly('Ana', 'Bia')
    end
  end

  describe 'PUT performance_goals' do
    let(:next_month) { (Date.current.beginning_of_month >> 1).strftime('%Y-%m') }

    def put_goals(user, target, month_value = next_month)
      put goals_url, params: { month: month_value, goals: [{ target_type: 'user', target_id: target.id, metric: 'nps', value: 70 }] },
                     headers: user.create_new_auth_token, as: :json
    end

    it 'grava e a meta passa a valer no mes' do
      put_goals(admin, ana)

      expect(response).to have_http_status(:success)
      ana_goals = response.parsed_body['users'].find { |u| u['id'] == ana.id }['goals']
      expect(ana_goals['nps']).to eq('value' => 70.0, 'since_month' => next_month)
    end

    it 'supervisor de time nao grava meta de atendente de outro time (403)' do
      supervisor = create(:user, account: account, role: :administrator)
      AccountUser.find_by(account: account, user: supervisor).update!(supervised_team_ids: [team.id])

      put_goals(supervisor, caio)
      expect(response).to have_http_status(:forbidden)
    end

    it 'mes passado responde 422' do
      put_goals(admin, ana, (Date.current.beginning_of_month << 1).strftime('%Y-%m'))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'atendente nao define meta' do
      put_goals(ana, ana)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH performance_goals/visibility' do
    it 'so administrador e supervisor da conta mudam quem enxerga' do
      patch "#{goals_url}/visibility", params: { visibility: 'own' }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      patch "#{goals_url}/visibility", params: { visibility: 'everyone' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(account.reload.goals_visibility).to eq('everyone')
    end
  end
end
