require 'rails_helper'

# Ligar e desligar feature PELA TELA da conta. Até 28/08/2026 isso só existia pelo console, pelo
# super_admin (Administrate) ou pela Platform API, que exige token de PlatformApp — nenhum ao alcance
# do administrador da conta.
RSpec.describe 'Api::V1::Accounts features', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/features" }

  describe 'GET' do
    it 'nega sem autenticacao' do
      get url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'nega para agente comum' do
      get url, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    # A tela precisa mostrar o que EXISTE para poder oferecer; o `_account.json.jbuilder` segue
    # expondo só as ligadas, e isso não muda para o resto do front.
    it 'devolve o catalogo INTEIRO, e nao so as ligadas' do
      get url, headers: admin.create_new_auth_token

      nomes = response.parsed_body['features'].pluck('name')
      expect(response).to have_http_status(:success)
      expect(nomes.size).to eq(65)
      expect(nomes).to include('automations', 'saml')
    end

    it 'diz de cada uma se esta ligada e como a tela deve trata-la' do
      account.enable_features!('campaigns')

      get url, headers: admin.create_new_auth_token

      campanhas = response.parsed_body['features'].find { |f| f['name'] == 'campaigns' }
      expect(campanhas).to include('enabled' => true, 'available' => true, 'premium' => false)
    end

    # `available: false` é o que faz a tela TRAVAR o interruptor em vez de só avisar.
    it 'marca como indisponiveis as que nao cabem no bitmask' do
      get url, headers: admin.create_new_auth_token

      indisponiveis = response.parsed_body['features'].reject { |f| f['available'] }.pluck('name')
      expect(indisponiveis).to contain_exactly('conversation_required_attributes', 'advanced_assignment')
    end
  end

  describe 'PATCH' do
    it 'nega para agente comum' do
      patch url, params: { features: { campaigns: true } }, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'liga e desliga' do
      patch url, params: { features: { campaigns: true } }, headers: admin.create_new_auth_token
      expect(account.reload.feature_enabled?('campaigns')).to be(true)

      patch url, params: { features: { campaigns: false } }, headers: admin.create_new_auth_token
      expect(account.reload.feature_enabled?('campaigns')).to be(false)
    end

    # O CASO QUE IMPORTA. `selected_feature_flags=` (FlagShihTzu) zera todos os bits antes de ligar os
    # enviados; se o endpoint usasse aquilo, uma requisição parcial apagaria tudo que a conta tinha.
    # É o mesmo estrago do "salvar apagava o config do agente" já corrigido neste fork.
    it 'e MERGE: mexer numa feature nao apaga as outras' do
      account.enable_features!('campaigns', 'reports', 'macros')

      patch url, params: { features: { macros: false } }, headers: admin.create_new_auth_token

      ligadas = account.reload.enabled_features.keys
      expect(ligadas).to include('campaigns', 'reports')
      expect(ligadas).not_to include('macros')
    end

    it 'devolve o catalogo atualizado, para a tela nao precisar recarregar' do
      patch url, params: { features: { campaigns: true } }, headers: admin.create_new_auth_token

      campanhas = response.parsed_body['features'].find { |f| f['name'] == 'campaigns' }
      expect(campanhas['enabled']).to be(true)
    end
  end

  # Sem esta guarda a requisição morreria com RangeError, porque o bit não cabe no bigint.
  describe 'as features que nao cabem no bitmask' do
    it 'recusa ligar, com mensagem que explica o motivo' do
      patch url, params: { features: { advanced_assignment: true } }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('advanced_assignment')
    end

    it 'nao grava nada quando uma do lote e bloqueada' do
      patch url, params: { features: { campaigns: true, advanced_assignment: true } },
                 headers: admin.create_new_auth_token

      expect(account.reload.feature_enabled?('campaigns')).to be(false)
    end

    # Desligar continua permitido: serve para consertar conta que ficou com bit inválido por outro
    # caminho.
    it 'permite DESLIGAR uma delas' do
      patch url, params: { features: { advanced_assignment: false } }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
    end
  end

  describe 'entrada invalida' do
    it 'recusa nome de feature que nao existe' do
      patch url, params: { features: { feature_que_nao_existe: true } }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('feature_que_nao_existe')
    end
  end

  # O Captain v1 é legado e anda junto do v2 — mesma regra que o super_admin já aplica.
  describe 'Captain v1 acompanha o v2' do
    it 'desligar o v2 desliga o legado junto' do
      account.enable_features!('captain_integration', 'captain_integration_v2')

      patch url, params: { features: { captain_integration_v2: false } }, headers: admin.create_new_auth_token

      expect(account.reload.feature_enabled?('captain_integration')).to be(false)
    end
  end
end
