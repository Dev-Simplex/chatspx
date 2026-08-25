require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::DistribuicaoPoliciesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:time) { create(:team, account: account) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:carla) { create(:user, account: account, role: :agent, name: 'Carla') }

  def membro(user, equipe = time)
    create(:team_member, team: equipe, user: user)
    user
  end

  def entrada(user, cap: 0, ativo: true)
    { user_id: user.id, ativo: ativo, cap: cap }
  end

  def politica_de(equipe)
    Spx::Distribuicao::Policy.find_by(account_id: account.id, team_id: equipe.id)
  end

  # ------------------------------------------------------------------ acesso

  describe 'acesso' do
    it 'nega sem autenticação' do
      get "/api/v1/accounts/#{account.id}/distribuicao_policies"
      expect(response).to have_http_status(:unauthorized)
    end

    # Quem está NO pool não pode mexer no pool: a tela decide quem recebe lead.
    it 'nega para agente comum em toda a superfície de escrita' do
      get "/api/v1/accounts/#{account.id}/distribuicao_policies", headers: agente.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}", headers: agente.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { modo: 'rodizio' } }, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(politica_de(time)).to be_nil

      delete "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}", headers: agente.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ------------------------------------------------------------------- index

  describe 'GET /distribuicao_policies' do
    it 'lista as políticas da conta e os times com seus membros' do
      membro(ana)
      policy = create(:distribuicao_policy, account: account, team: time, pool: [{ 'user_id' => ana.id, 'ativo' => true, 'cap' => 3 }])

      get "/api/v1/accounts/#{account.id}/distribuicao_policies", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      corpo = response.parsed_body
      expect(corpo['policies'].pluck('id')).to eq([policy.id])
      expect(corpo['policies'].first['team_name']).to eq(time.name)
      expect(corpo['policies'].first['pool']).to eq([{ 'user_id' => ana.id, 'ativo' => true, 'cap' => 3, 'name' => 'Ana' }])
      listado = corpo['teams'].find { |t| t['id'] == time.id }
      expect(listado['members'].pluck('id')).to eq([ana.id])
      expect(listado['members'].first).to include('email' => ana.email)
    end

    it 'não lista política de outra conta' do
      outra = create(:account)
      create(:distribuicao_policy, account: outra, team: create(:team, account: outra))

      get "/api/v1/accounts/#{account.id}/distribuicao_policies", headers: administrator.create_new_auth_token

      expect(response.parsed_body['policies']).to be_empty
    end

    # A tela precisa poder RELIGAR um time que alguém desligou.
    it 'inclui política inativa' do
      create(:distribuicao_policy, account: account, team: time, ativo: false)
      get "/api/v1/accounts/#{account.id}/distribuicao_policies", headers: administrator.create_new_auth_token
      expect(response.parsed_body['policies'].first['ativo']).to be(false)
    end
  end

  # -------------------------------------------------------------------- show

  describe 'GET /distribuicao_policies/:team_id' do
    it 'devolve policy nula e os membros quando o time ainda não tem política' do
      membro(ana)
      get "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['policy']).to be_nil
      expect(response.parsed_body['team']).to include('id' => time.id)
      expect(response.parsed_body['members'].pluck('id')).to eq([ana.id])
    end

    it 'recusa time de outra conta' do
      alheio = create(:team, account: create(:account))
      get "/api/v1/accounts/#{account.id}/distribuicao_policies/#{alheio.id}", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------------ upsert

  describe 'PUT /distribuicao_policies/:team_id' do
    # Upsert: o primeiro PUT num time sem política CRIA.
    def primeiro_put!
      membro(ana)
      membro(bruno)
      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { ativo: true, modo: 'rodizio', modo_posse: 'designacao', continuidade_ativa: true,
                              continuidade_dias: 45, sla_assumir_minutos: 10, repasse_automatico: true,
                              max_repasses: 3, gatilho_sem_ia: true,
                              pool: [entrada(ana, cap: 5), entrada(bruno)] } },
          headers: administrator.create_new_auth_token, as: :json
    end

    it 'cria a política no primeiro PUT' do
      primeiro_put!

      expect(response).to have_http_status(:success)
      criada = response.parsed_body['policy']
      expect(criada).to include('team_id' => time.id, 'modo' => 'rodizio', 'modo_posse' => 'designacao',
                                'continuidade_dias' => 45, 'sla_assumir_minutos' => 10,
                                'repasse_automatico' => true, 'max_repasses' => 3, 'gatilho_sem_ia' => true)
      expect(criada['pool']).to eq([
                                     { 'user_id' => ana.id, 'ativo' => true, 'cap' => 5, 'name' => 'Ana' },
                                     { 'user_id' => bruno.id, 'ativo' => true, 'cap' => 0, 'name' => 'Bruno' }
                                   ])
      expect(politica_de(time)).to be_present
    end

    it 'atualiza a MESMA política no segundo PUT' do
      primeiro_put!
      criada_id = response.parsed_body['policy']['id']

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { modo: 'fila', pool: [entrada(bruno, ativo: false)] } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['policy']['id']).to eq(criada_id)
      expect(Spx::Distribuicao::Policy.where(account_id: account.id, team_id: time.id).count).to eq(1)
      politica = politica_de(time)
      expect(politica.modo).to eq('fila')
      # Chave não enviada não é "apague": modo_posse do primeiro PUT sobrevive.
      expect(politica.modo_posse).to eq('designacao')
      expect(politica.pool).to eq([{ 'user_id' => bruno.id, 'ativo' => false, 'cap' => 0 }])
    end

    # A ordem do array É o rodízio (DistribuirService#proximo_rodizio anda por ela). Ordenar
    # o pool em qualquer ponto do round-trip trocaria a vez de quem recebe.
    it 'preserva a ORDEM do pool no round-trip' do
      [carla, ana, bruno].each { |u| membro(u) }
      ordem = [carla.id, ana.id, bruno.id]

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { modo: 'rodizio', pool: [entrada(carla), entrada(ana), entrada(bruno)] } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['policy']['pool'].pluck('user_id')).to eq(ordem)
      expect(politica_de(time).pool.map { |e| e['user_id'] }).to eq(ordem)

      get "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}", headers: administrator.create_new_auth_token
      expect(response.parsed_body['policy']['pool'].pluck('user_id')).to eq(ordem)

      get "/api/v1/accounts/#{account.id}/distribuicao_policies", headers: administrator.create_new_auth_token
      expect(response.parsed_body['policies'].first['pool'].pluck('user_id')).to eq(ordem)
    end

    it 'recusa pool com quem não é membro atual do time, dizendo quem' do
      membro(ana)

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { modo: 'rodizio', pool: [entrada(ana), entrada(bruno)] } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('Bruno', bruno.id.to_s)
      expect(response.parsed_body['errors'].join).not_to include('Ana')
      expect(politica_de(time)).to be_nil
    end

    it 'recusa pool com user_id repetido' do
      membro(ana)

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { modo: 'rodizio', pool: [entrada(ana), entrada(ana, cap: 2)] } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('repetido')
      expect(politica_de(time)).to be_nil
    end

    it 'recusa time de outra conta' do
      outra = create(:account)
      alheio = create(:team, account: outra)
      forasteiro = membro(create(:user, account: outra, role: :agent), alheio)

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{alheio.id}",
          params: { policy: { modo: 'rodizio', pool: [entrada(forasteiro)] } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(politica_de(alheio)).to be_nil
    end

    it 'recusa destino de pool esgotado que não é da conta' do
      de_fora = create(:user, account: create(:account), role: :agent)

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { modo: 'rodizio', pool: [], pool_esgotado_destino_user_id: de_fora.id } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('pool esgotado')
      expect(politica_de(time)).to be_nil
    end

    it 'aceita destino de pool esgotado da conta e aceita limpá-lo depois' do
      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { modo: 'rodizio', pool_esgotado_destino_user_id: agente.id } },
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(politica_de(time).pool_esgotado_destino_user_id).to eq(agente.id)

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { pool_esgotado_destino_user_id: nil } },
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(politica_de(time).pool_esgotado_destino_user_id).to be_nil
    end

    it 'recusa valores fora do domínio (modo, modo_posse, sla, max_repasses, continuidade_dias)' do
      [
        { modo: 'banana' },
        { modo_posse: 'ninguem' },
        { sla_assumir_minutos: 0 },
        { max_repasses: -1 },
        { continuidade_dias: 0 }
      ].each do |atributo|
        put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
            params: { policy: atributo }, headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity), "aceitou #{atributo.inspect}"
        expect(response.parsed_body['errors']).to be_present
        expect(politica_de(time)).to be_nil
      end
    end

    it 'recusa cap negativo' do
      membro(ana)
      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { modo: 'rodizio', pool: [entrada(ana, cap: -1)] } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('cap')
    end

    # `produtos` mora dentro da entrada do pool e NÃO está no contrato da tela. Se o save
    # gravasse o array cru do front, o filtro por produto de quem foi configurado por rake
    # sumiria em silêncio no primeiro clique em "salvar".
    it 'preserva chaves do pool que a tela não conhece (produtos)' do
      membro(ana)
      create(:distribuicao_policy, account: account, team: time,
                                   pool: [{ 'user_id' => ana.id, 'ativo' => true, 'cap' => 1,
                                            'produtos' => [{ 'produto' => 'alto-padrao', 'valor_max' => 900 }] }])

      put "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}",
          params: { policy: { pool: [entrada(ana, cap: 7)] } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      entrada_gravada = politica_de(time).pool.first
      expect(entrada_gravada['cap']).to eq(7)
      expect(entrada_gravada['produtos']).to eq([{ 'produto' => 'alto-padrao', 'valor_max' => 900 }])
    end
  end

  # ----------------------------------------------------------------- destroy

  describe 'DELETE /distribuicao_policies/:team_id' do
    it 'remove a política do time (desliga o motor) e é idempotente' do
      create(:distribuicao_policy, account: account, team: time)

      delete "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:no_content)
      expect(politica_de(time)).to be_nil

      delete "/api/v1/accounts/#{account.id}/distribuicao_policies/#{time.id}", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:no_content)
    end

    it 'não remove política de time de outra conta' do
      outra = create(:account)
      alheio = create(:team, account: outra)
      create(:distribuicao_policy, account: outra, team: alheio)

      delete "/api/v1/accounts/#{account.id}/distribuicao_policies/#{alheio.id}", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(Spx::Distribuicao::Policy.find_by(account_id: outra.id, team_id: alheio.id)).to be_present
    end
  end
end
