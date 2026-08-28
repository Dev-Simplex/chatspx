require 'rails_helper'

# "supervisor" precisa valer em toda superfície que atribui papel, não só no
# Console de Super Admin — antes destas linhas a API devolvia 500 (ArgumentError
# do enum) para o mesmo valor que o console oferece no seletor.
RSpec.describe 'Agents API: papel supervisor', type: :request do
  let!(:account) { create(:account) }
  let!(:team) { create(:team, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:account_user) { agent.account_users.find_by(account_id: account.id) }

  describe 'PATCH /api/v1/accounts/{account.id}/agents/{id}' do
    it 'aceita supervisor e grava administrador + supervisão dos times informados' do
      patch "/api/v1/accounts/#{account.id}/agents/#{agent.id}",
            params: { role: 'supervisor', supervised_team_ids: [team.id] },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account_user.reload.role).to eq('administrator')
      expect(account_user.supervised_team_ids).to contain_exactly(team.id)
      expect(account_user.console_role).to eq('supervisor')
    end

    it 'sem times informados, supervisiona todos os da conta' do
      patch "/api/v1/accounts/#{account.id}/agents/#{agent.id}",
            params: { role: 'supervisor' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account_user.reload.supervised_team_ids).to contain_exactly(team.id)
    end

    # A guarda que impede supervisor de trocar função de alguém não muda: o endpoint
    # segue admin-only para qualquer chave que não seja `name`.
    it 'segue recusando um supervisor que tente trocar papel' do
      supervisor = create(:user, account: account, role: :agent)
      create(:team_supervisor, team: team, user: supervisor)
      create(:team_member, team: team, user: agent)

      patch "/api/v1/accounts/#{account.id}/agents/#{agent.id}",
            params: { role: 'supervisor' }, headers: supervisor.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account_user.reload.supervised_team_ids).to be_empty
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/agents' do
    it 'cria como administrador supervisor em vez de estourar' do
      post "/api/v1/accounts/#{account.id}/agents",
           params: { name: 'Nova', email: 'nova.supervisora@exemplo.test', role: 'supervisor' },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      novo = AccountUser.find_by(account_id: account.id, user_id: User.from_email('nova.supervisora@exemplo.test').id)
      expect(novo.role).to eq('administrator')
      expect(novo.supervised_team_ids).to contain_exactly(team.id)
    end
  end
end
