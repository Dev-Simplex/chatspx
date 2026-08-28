require 'rails_helper'

# O papel "supervisor" no Console de Super Admin é uma opção de TELA sobre
# administrador + team_supervisors. Como isso mora em views do Administrate, o
# spec exercita o render junto com o round-trip de gravação.
RSpec.describe 'Super Admin: papel supervisor', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }
  # Team normaliza o nome para minúsculas — daí a expectativa em caixa baixa.
  let!(:team) { create(:team, account: account, name: 'suporte') }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:account_user) { user.account_users.find_by(account_id: account.id) }

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'render do formulário' do
    it 'oferece supervisor ao lado de agent e administrator na página do usuário' do
      get "/super_admin/users/#{user.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('supervisor')
      expect(response.body).to include('Supervised teams')
    end

    # Na página da CONTA a conta é conhecida, então o seletor lista os times dela.
    it 'lista os times da conta na página da conta' do
      get "/super_admin/accounts/#{account.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('suporte')
    end

    it 'abre a edição de um vínculo existente' do
      get "/super_admin/account_users/#{account_user.id}/edit"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('supervisor')
    end
  end

  describe 'gravação' do
    it 'cria como administrador no banco, com a supervisão escolhida' do
      novo = create(:user)

      post '/super_admin/account_users', params: {
        account_user: { account_id: account.id, user_id: novo.id, console_role: 'supervisor', supervised_team_ids: [team.id] }
      }

      vinculo = AccountUser.find_by(account_id: account.id, user_id: novo.id)
      expect(vinculo.role).to eq('administrator')
      expect(vinculo.supervised_team_ids).to contain_exactly(team.id)
      expect(vinculo.console_role).to eq('supervisor')
    end

    it 'troca papel e supervisão pela edição' do
      patch "/super_admin/account_users/#{account_user.id}", params: {
        account_user: { console_role: 'supervisor', supervised_team_ids: [team.id] }
      }
      expect(account_user.reload.console_role).to eq('supervisor')

      patch "/super_admin/account_users/#{account_user.id}", params: {
        account_user: { console_role: 'administrator', supervised_team_ids: [] }
      }
      expect(account_user.reload.role).to eq('administrator')
      expect(account_user.supervised_team_ids).to be_empty
    end
  end
end
