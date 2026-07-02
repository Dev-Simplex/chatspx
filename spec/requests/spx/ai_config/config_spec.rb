require 'rails_helper'

# Receptor spx/ai_config — action #assistants (seletor de agentes do Almirante).
RSpec.describe 'Spx::AiConfig::Config', type: :request do
  let(:account) { create(:account) }
  let(:platform_app) { create(:platform_app) }
  let(:token) { platform_app.access_token.token }

  describe 'GET /spx/ai_config/accounts/:account_id/assistants' do
    let(:url) { "/spx/ai_config/accounts/#{account.id}/assistants" }

    it 'lista os agentes (id + name) da conta, ordenados por id' do
      a1 = create(:captain_assistant, account: account, name: 'Clara')
      a2 = create(:captain_assistant, account: account, name: 'Bruna')

      get url, headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['assistants']).to eq(
        [{ 'id' => a1.id, 'name' => 'Clara' }, { 'id' => a2.id, 'name' => 'Bruna' }]
      )
    end

    it 'devolve lista vazia quando a conta nao tem agentes' do
      get url, headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['assistants']).to eq([])
    end

    it 'exige token de PlatformApp (401 sem token)' do
      get url, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
