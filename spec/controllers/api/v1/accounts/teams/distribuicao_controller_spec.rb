require 'rails_helper'

# A API que a tela do time usa para configurar o rodízio. Chegou pelo PR #67 sem nenhum teste,
# e é ela que decide quem pode mexer na fila de leads de um time.
RSpec.describe 'Api::V1::Accounts::Teams::Distribuicao', type: :request do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:gerente) { create(:user, account: account, role: :agent) }
  let(:membro) { create(:user, account: account, role: :agent) }

  let(:url) { "/api/v1/accounts/#{account.id}/teams/#{team.id}/distribuicao" }

  before { create(:team_member, team: team, user: membro) }

  describe 'GET (quem pode ver)' do
    it 'nega sem autenticacao' do
      get url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'nega para agente comum, que nao gerencia o time' do
      get url, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'permite para o admin da conta' do
      get url, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
    end

    # É o gerente quem sabe quem entrou de férias: a mesma regra que já governa a gestão de
    # membros do time.
    it 'permite para o supervisor daquele time, mesmo sendo agente' do
      create(:team_supervisor, team: team, user: gerente)

      get url, headers: gerente.create_new_auth_token

      expect(response).to have_http_status(:success)
    end

    it 'nao vaza time de outra conta' do
      outro = create(:team, account: create(:account))

      get "/api/v1/accounts/#{account.id}/teams/#{outro.id}/distribuicao",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET (time ainda sem politica)' do
    # Devolver 404 obrigaria a tela a tratar "ainda não configurado" como falha. Com o esqueleto,
    # ela renderiza os defaults e mostra o que o time VAI ser ao salvar.
    it 'devolve o esqueleto com configurado: false em vez de 404' do
      get url, headers: admin.create_new_auth_token

      corpo = response.parsed_body
      expect(response).to have_http_status(:success)
      expect(corpo['configurado']).to be(false)
      expect(corpo['politica']).to be_present
    end
  end

  describe 'PATCH' do
    it 'cria a politica no primeiro save' do
      expect do
        patch url, params: { ativo: true, sla_assumir_minutos: 45 },
                   headers: admin.create_new_auth_token
      end.to change(Spx::Distribuicao::Policy, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(Spx::Distribuicao::Policy.last.sla_assumir_minutos).to eq(45)
    end

    it 'nega para agente comum' do
      patch url, params: { ativo: true }, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
      expect(Spx::Distribuicao::Policy.count).to eq(0)
    end

    # A ordem do pool É a ordem do rodízio: reordenar não pode ser reinterpretado pelo servidor.
    it 'preserva a ORDEM enviada no pool' do
      outro = create(:user, account: account, role: :agent)
      create(:team_member, team: team, user: outro)

      patch url, params: { ativo: true, pool: [{ user_id: outro.id }, { user_id: membro.id }] },
                 headers: admin.create_new_auth_token

      expect(Spx::Distribuicao::Policy.last.pool.map { |e| e['user_id'] }).to eq([outro.id, membro.id])
    end

    # Sem allowlist, o jsonb guarda para sempre qualquer coisa que mandarem e vira lixo que
    # ninguém sabe de onde veio.
    it 'descarta chave desconhecida na entrada do pool' do
      patch url, params: { ativo: true, pool: [{ user_id: membro.id, ativo: true, xpto: 'lixo' }] },
                 headers: admin.create_new_auth_token

      expect(Spx::Distribuicao::Policy.last.pool.first.keys).not_to include('xpto')
    end

    it 'nao aceita usuario de outra conta no pool' do
      forasteiro = create(:user, account: create(:account), role: :agent)

      patch url, params: { ativo: true, pool: [{ user_id: forasteiro.id }] },
                 headers: admin.create_new_auth_token

      expect(Spx::Distribuicao::Policy.last.pool.map { |e| e['user_id'] }).not_to include(forasteiro.id)
    end

    it 'guarda a suspensao com prazo da entrada do pool' do
      volta = 3.days.from_now.to_date.to_s

      patch url, params: { ativo: true,
                           pool: [{ user_id: membro.id, suspenso_ate: volta, motivo: 'ferias' }] },
                 headers: admin.create_new_auth_token

      entrada = Spx::Distribuicao::Policy.last.pool.first
      expect(entrada['suspenso_ate']).to eq(volta)
      expect(entrada['motivo']).to eq('ferias')
    end
  end

  # Os defaults da tela TEM de espelhar os das colunas: divergindo, o time ainda nao configurado
  # ve um numero que nao e o que o banco vai gravar, e o primeiro save persiste o da tela.
  describe 'defaults do esqueleto' do
    let(:colunas) { Spx::Distribuicao::Policy.columns_hash }

    def esqueleto
      get url, headers: admin.create_new_auth_token
      response.parsed_body['politica']
    end

    it 'max_repasses bate com o default da coluna (era 3 na tela contra 2 no banco)' do
      esperado = colunas['max_repasses'].default.to_i

      expect(esqueleto['max_repasses']).to eq(esperado)
      expect(esperado).to eq(2)
    end

    # Serializado a partir das chaves de PADROES: faltando ali, o campo NAO volta na resposta, a
    # tela o le como indefinido e o salva como falso — desligando em silencio quem o tinha ligado.
    it 'devolve gatilho_sem_ia, senao a tela nao consegue nem mostrar nem preservar o valor' do
      expect(esqueleto).to have_key('gatilho_sem_ia')
    end

    it 'todo campo booleano do esqueleto bate com o default da coluna' do
      atual = esqueleto
      %w[repasse_automatico sla_respeita_horario expirado_conta_como_recebido
         gatilho_sem_ia espelho_vista so_online].each do |campo|
        expect(atual[campo]).to eq(colunas[campo].default == 'true'), "#{campo} divergiu do banco"
      end
    end

    # A UNICA excecao, e de proposito: a coluna nasce `true`, mas time SEM politica tem de aparecer
    # DESLIGADO. Espelhar o banco aqui faria a tela afirmar que o rodizio esta ativo num time que
    # nao tem politica nenhuma, e o primeiro save o ligaria sem ninguem ter pedido.
    it 'ativo e a excecao: nasce desligado na tela mesmo com a coluna default true' do
      expect(colunas['ativo'].default).to eq('true')
      expect(esqueleto['ativo']).to be(false)
    end
  end

  describe 'gatilho sem IA' do
    # E o interruptor do caminho "a conversa caiu no time por transferencia manual, fluxo ou
    # regra" — sem ele o Motor so agia no handoff da IA.
    it 'grava e devolve o valor ligado' do
      patch url, params: { ativo: true, gatilho_sem_ia: true },
                 headers: admin.create_new_auth_token

      expect(Spx::Distribuicao::Policy.last.gatilho_sem_ia).to be(true)
      expect(response.parsed_body['politica']['gatilho_sem_ia']).to be(true)
    end

    it 'nao desliga sozinho num save que nao fala dele' do
      patch url, params: { ativo: true, gatilho_sem_ia: true }, headers: admin.create_new_auth_token
      patch url, params: { sla_assumir_minutos: 45 }, headers: admin.create_new_auth_token

      expect(Spx::Distribuicao::Policy.last.gatilho_sem_ia).to be(true)
    end
  end
end
