require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::UnidadesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/unidades' do
    it 'nega acesso a quem não está autenticado' do
      get "/api/v1/accounts/#{account.id}/unidades"

      expect(response).to have_http_status(:unauthorized)
    end

    # §9.2: perfis admin. Sem permissão por unidade, sem escopo por gerente.
    it 'nega acesso a agente' do
      get "/api/v1/accounts/#{account.id}/unidades", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when it is an authenticated administrator' do
      let!(:unidade) do
        create(:spx_unidade, account: account, nome: 'Sinop Centro', cidade: 'Sinop',
                             etiquetas: %w[MT Matriz])
      end

      before do
        create(:spx_unidade_horario, unidade: unidade, dia_semana: 1, abre: '08:00', fecha: '18:00')
      end

      it 'lista as unidades da conta com a grade da semana' do
        get "/api/v1/accounts/#{account.id}/unidades", headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        payload = response.parsed_body['unidades']
        expect(payload.length).to eq(1)
        expect(payload.first['nome']).to eq('Sinop Centro')
        expect(payload.first['etiquetas']).to eq(%w[mt matriz])
      end

      # A grade sai de segunda a domingo, que é como se lê no Brasil — e não na ordem do `wday`.
      it 'devolve a grade na ordem de leitura' do
        get "/api/v1/accounts/#{account.id}/unidades", headers: administrator.create_new_auth_token

        dias = response.parsed_body['unidades'].first['grade'].pluck('dia_semana')
        expect(dias).to eq([1, 2, 3, 4, 5, 6, 0])
      end

      # A distinção que impede a tela de inventar: dia sem linha é "não sei", não "fechada".
      it 'distingue dia não cadastrado de dia fechado' do
        get "/api/v1/accounts/#{account.id}/unidades", headers: administrator.create_new_auth_token

        grade = response.parsed_body['unidades'].first['grade'].index_by { |dia| dia['dia_semana'] }
        expect(grade[1]['cadastrado']).to be true
        expect(grade[1]['faixas']).to eq(['08:00 às 18:00'])
        expect(grade[0]['cadastrado']).to be false
        expect(grade[0]['faixas']).to be_empty
      end

      it 'devolve as etiquetas da conta para alimentar o alvo da exceção' do
        get "/api/v1/accounts/#{account.id}/unidades", headers: administrator.create_new_auth_token

        expect(response.parsed_body['etiquetas']).to eq(%w[matriz mt])
      end

      it 'mantém a unidade inativa na lista, marcada' do
        create(:spx_unidade, account: account, nome: 'Fechada', ativa: false)

        get "/api/v1/accounts/#{account.id}/unidades", headers: administrator.create_new_auth_token

        inativa = response.parsed_body['unidades'].find { |u| u['nome'] == 'Fechada' }
        expect(inativa['ativa']).to be false
      end

      it 'não enxerga unidade de outra conta' do
        create(:spx_unidade, account: create(:account), nome: 'De outro cliente')

        get "/api/v1/accounts/#{account.id}/unidades", headers: administrator.create_new_auth_token

        nomes = response.parsed_body['unidades'].pluck('nome')
        expect(nomes).not_to include('De outro cliente')
      end
    end
  end
end
