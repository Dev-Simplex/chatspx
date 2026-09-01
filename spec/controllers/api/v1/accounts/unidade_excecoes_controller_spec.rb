require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::UnidadeExcecoesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:unidade) { create(:spx_unidade, account: account, nome: 'Sinop Centro', etiquetas: ['MT']) }

  describe 'GET /api/v1/accounts/{account.id}/unidade_excecoes' do
    it 'nega acesso a agente' do
      get "/api/v1/accounts/#{account.id}/unidade_excecoes", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    # O ponto do desenho: exceção vencida morre sozinha. Listá-la devolveria ao operador a
    # limpeza manual que o n8n exigia — que é a dor que este contrato existe para matar.
    it 'não lista exceção que já venceu' do
      create(:spx_unidade_excecao, account: account, unidade: unidade,
                                   data_inicio: 10.days.ago.to_date, data_fim: 9.days.ago.to_date)
      futura = create(:spx_unidade_excecao, account: account, unidade: unidade,
                                            data_inicio: 3.days.from_now.to_date, data_fim: 3.days.from_now.to_date)

      get "/api/v1/accounts/#{account.id}/unidade_excecoes", headers: administrator.create_new_auth_token

      expect(response.parsed_body.pluck('id')).to eq([futura.id])
    end

    it 'não enxerga exceção de outra conta' do
      outra = create(:account)
      create(:spx_unidade_excecao, account: outra, data_inicio: Time.zone.today, data_fim: Time.zone.today,
                                   motivo: 'de outro cliente')

      get "/api/v1/accounts/#{account.id}/unidade_excecoes", headers: administrator.create_new_auth_token

      expect(response.parsed_body.pluck('motivo')).not_to include('de outro cliente')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/unidade_excecoes' do
    it 'nega criação por agente' do
      post "/api/v1/accounts/#{account.id}/unidade_excecoes",
           params: { unidade_excecao: { data_inicio: Time.zone.today, data_fim: Time.zone.today, fechada: true } },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    # Campanha nunca é uma loja: o caso que justifica a etiqueta.
    it 'cria exceção por etiqueta, valendo para o grupo' do
      post "/api/v1/accounts/#{account.id}/unidade_excecoes",
           params: { unidade_excecao: { etiqueta: 'MT', data_inicio: 3.days.from_now.to_date,
                                        data_fim: 3.days.from_now.to_date, fechada: false,
                                        abre: '08:00', fecha: '13:00', motivo: 'campanha de aniversário' } },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['etiqueta']).to eq('mt')
      expect(body['horario']).to eq('08:00 às 13:00')
      expect(body['especificidade']).to eq(1)
    end

    it 'cria exceção de conta inteira quando não vem alvo nenhum' do
      post "/api/v1/accounts/#{account.id}/unidade_excecoes",
           params: { unidade_excecao: { data_inicio: 5.days.from_now.to_date, data_fim: 5.days.from_now.to_date,
                                        fechada: true, motivo: 'feriado nacional' } },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['especificidade']).to eq(0)
    end

    # Fronteira de conta: id de unidade alheia não pode virar exceção gravada aqui.
    it 'devolve 404 para unidade de outra conta em vez de gravar' do
      alheia = create(:spx_unidade, account: create(:account))

      post "/api/v1/accounts/#{account.id}/unidade_excecoes",
           params: { unidade_excecao: { unidade_id: alheia.id, data_inicio: Time.zone.today,
                                        data_fim: Time.zone.today, fechada: true } },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(Spx::UnidadeExcecao.where(account_id: account.id).count).to eq(0)
    end

    it 'recusa data_fim anterior a data_inicio' do
      post "/api/v1/accounts/#{account.id}/unidade_excecoes",
           params: { unidade_excecao: { data_inicio: 5.days.from_now.to_date, data_fim: Time.zone.today,
                                        fechada: true } },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/unidade_excecoes/{id}' do
    it 'apaga a exceção' do
      excecao = create(:spx_unidade_excecao, account: account, unidade: unidade,
                                             data_inicio: Time.zone.today, data_fim: Time.zone.today)

      delete "/api/v1/accounts/#{account.id}/unidade_excecoes/#{excecao.id}",
             headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(Spx::UnidadeExcecao.exists?(excecao.id)).to be false
    end

    it 'não apaga exceção de outra conta' do
      alheia = create(:spx_unidade_excecao, account: create(:account),
                                            data_inicio: Time.zone.today, data_fim: Time.zone.today)

      delete "/api/v1/accounts/#{account.id}/unidade_excecoes/#{alheia.id}",
             headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(Spx::UnidadeExcecao.exists?(alheia.id)).to be true
    end
  end
end
