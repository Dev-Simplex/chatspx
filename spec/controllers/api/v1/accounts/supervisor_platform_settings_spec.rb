require 'rails_helper'

# Supervisor de time (linha em team_supervisors) perde SEIS itens de configuração de
# plataforma, mesmo sendo administrador da conta. O que este spec protege é o par:
# a GESTÃO nega, a LEITURA que a tela de atendimento usa continua passando — e nada
# muda para administrador comum nem para agente.
RSpec.describe 'Supervisor sem as configurações de plataforma', type: :request do
  let!(:account) { create(:account) }
  let!(:team) { create(:team, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:supervisor) { create(:user, account: account, role: :administrator) }

  before { create(:team_supervisor, team: team, user: supervisor) }

  describe 'Atributos personalizados' do
    let!(:definition) { create(:custom_attribute_definition, account: account) }

    it 'nega a gestão ao supervisor' do
      post "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
           params: { custom_attribute_definition: { attribute_display_name: 'x', attribute_key: 'x', attribute_model: 0 } },
           headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      delete "/api/v1/accounts/#{account.id}/custom_attribute_definitions/#{definition.id}",
             headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # Sem isto o supervisor abre uma conversa e os campos personalizados somem.
    it 'mantém a leitura que alimenta o painel do contato e da conversa' do
      get "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
          headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'não muda nada para administrador comum' do
      post "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
           params: { custom_attribute_definition: { attribute_display_name: 'y', attribute_key: 'y', attribute_model: 0 } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'Robôs' do
    let!(:agent_bot) { create(:agent_bot, account: account) }

    it 'nega a gestão ao supervisor' do
      post "/api/v1/accounts/#{account.id}/agent_bots",
           params: { name: 'bot' }, headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      patch "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}",
            params: { name: 'novo' }, headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # A tela da caixa de entrada lista os bots para mostrar qual está ligado.
    it 'mantém a listagem' do
      get "/api/v1/accounts/#{account.id}/agent_bots", headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'não muda nada para administrador comum' do
      post "/api/v1/accounts/#{account.id}/agent_bots",
           params: { name: 'bot' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'Macros' do
    let!(:macro) { create(:macro, account: account, created_by: admin, updated_by: admin, visibility: :global) }

    it 'nega a gestão ao supervisor' do
      post "/api/v1/accounts/#{account.id}/macros",
           params: { name: 'nova', actions: [{ action_name: 'add_label', action_params: ['x'] }] },
           headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      delete "/api/v1/accounts/#{account.id}/macros/#{macro.id}", headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # Executar macro dentro da conversa é uso legítimo e continua valendo.
    it 'mantém listar e executar' do
      get "/api/v1/accounts/#{account.id}/macros", headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      post "/api/v1/accounts/#{account.id}/macros/#{macro.id}/execute",
           params: { conversation_ids: [] }, headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'não muda nada para agente comum' do
      post "/api/v1/accounts/#{account.id}/macros",
           params: { name: 'nova', actions: [{ action_name: 'add_label', action_params: ['x'] }] },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'Integrações' do
    it 'nega conectar/desconectar um app ao supervisor' do
      post "/api/v1/accounts/#{account.id}/integrations/hooks",
           params: { app_id: 'dialogflow', settings: {} }, headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/accounts/#{account.id}/webhooks",
           params: { url: 'https://exemplo.test/hook' }, headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # A listagem de apps alimenta o botão de vídeo do Dyte e a sugestão de etiqueta
    # do OpenAI DENTRO da conversa — fechá-la quebraria a tela de atendimento.
    it 'mantém a listagem de apps que a tela de atendimento consulta' do
      get "/api/v1/accounts/#{account.id}/integrations/apps", headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'não muda nada para administrador comum' do
      post "/api/v1/accounts/#{account.id}/webhooks",
           params: { url: 'https://exemplo.test/hook' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'Fluxo de conversa' do
    it 'nega ao supervisor os ajustes que a tela grava' do
      patch "/api/v1/accounts/#{account.id}", params: { auto_resolve_after: 30 },
                                              headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # "Configurações da conta" não está entre os seis itens e segue funcionando.
    it 'mantém o resto das configurações da conta' do
      patch "/api/v1/accounts/#{account.id}", params: { name: 'Conta Renomeada' },
                                              headers: supervisor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(account.reload.name).to eq('Conta Renomeada')
    end

    it 'não muda nada para administrador comum' do
      patch "/api/v1/accounts/#{account.id}", params: { auto_resolve_after: 30 },
                                              headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'Console de Super Admin' do
    it 'recusa quem supervisiona time' do
      expect(SupervisorSettingsScope.blocked_from_console?(supervisor)).to be(true)
    end

    it 'não mexe em quem não supervisiona' do
      expect(SupervisorSettingsScope.blocked_from_console?(admin)).to be(false)
    end
  end
end
