require 'rails_helper'

# Proxy do painel do Captador na lateral da conversa (22 §1.3): sessão normal do ChatSPX, guardas
# da conversa e chamada assinada ao Captador em nome do atendente.
RSpec.describe 'Api::V1::Accounts::Integrations::Captador', type: :request do
  include CaptadorSigningHelpers

  let(:account) { create(:account) }
  let!(:hook) { captador_hook_for(account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, custom_attributes: { 'captador_lead_id' => 'lead-1' })
  end
  let(:base) { "/api/v1/accounts/#{account.id}/integrations/captador" }
  let(:lead_url) { "https://captador.test/integracao/chatspx/v1/leads?contact_id=#{contact.id}&conversation_id=#{conversation.display_id}" }
  let(:captador_lead) { { 'lead' => { 'id' => 'lead-1', 'nome' => 'Padaria X', 'etapa_id' => 2 }, 'etapas' => [], 'url' => nil } }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def get_lead(user = agent)
    get "#{base}/lead", params: { conversation_id: conversation.display_id }, headers: user.create_new_auth_token, as: :json
  end

  def signed_by_fork?(request, method, body = '')
    signed = "#{request.headers['X-Captador-Timestamp']}.#{method}.#{request.uri.request_uri}.#{body}"
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', hook.settings['shared_secret'], signed)}"
    request.headers['X-Captador-Assinatura'] == expected && request.headers['X-Captador-Instancia'] == 'inst-1' &&
      request.headers['X-Chatspx-Usuario'] == agent.id.to_s
  end

  describe 'GET lead' do
    it 'repassa o lead do Captador, pedido assinado em nome do atendente' do
      stub = stub_request(:get, lead_url).with { |request| signed_by_fork?(request, 'GET') }
                                         .to_return(status: 200, body: captador_lead.to_json, headers: json)
      get_lead

      expect(stub).to have_been_requested
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(captador_lead)
    end

    it 'usa o lead do contato quando a conversa não tem o carimbo' do
      conversation.update!(custom_attributes: {})
      contact.update!(custom_attributes: { 'captador_lead_id' => 'lead-1' })
      stub = stub_request(:get, lead_url).to_return(status: 200, body: captador_lead.to_json, headers: json)
      get_lead

      expect(stub).to have_been_requested
    end

    it 'não chama o Captador em conversa comum' do
      conversation.update!(custom_attributes: {})
      get_lead

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('lead' => nil, 'etapas' => [])
      expect(a_request(:any, /captador\.test/)).not_to have_been_made
    end

    it 'repassa o 403 acesso_pendente do Captador para o painel pedir acesso' do
      stub_request(:get, lead_url).to_return(status: 403, body: { codigo: 'acesso_pendente' }.to_json, headers: json)
      get_lead

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['codigo']).to eq('acesso_pendente')
    end

    it 'devolve 502 quando o Captador cai, demora ou recusa a assinatura' do
      stub_request(:get, lead_url).to_timeout
      get_lead
      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body['error_code']).to eq('captador_unavailable')

      stub_request(:get, lead_url).to_return(status: 500)
      get_lead
      expect(response).to have_http_status(:bad_gateway)

      stub_request(:get, lead_url).to_return(status: 401)
      get_lead
      expect(response).to have_http_status(:bad_gateway)
    end

    it 'aplica a guarda de time da conversa' do
      conversation.update!(team: create(:team, account: account))
      get_lead

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:any, /captador\.test/)).not_to have_been_made
    end

    it 'exige sessão' do
      get "#{base}/lead", params: { conversation_id: conversation.display_id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'responde 404 com o app desligado na conta' do
      account.update!(captador_integration: false)
      get_lead

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error_code']).to eq('captador_disabled')
    end
  end

  describe 'POST mover' do
    let(:mover_url) { 'https://captador.test/integracao/chatspx/v1/leads/lead-1/mover' }

    def move(params)
      post "#{base}/mover", params: params, headers: agent.create_new_auth_token, as: :json
    end

    it 'move o lead gravado na conversa, ignorando o que o navegador mandar' do
      stub = stub_request(:post, mover_url)
             .with(body: { etapa_id: 3 }.to_json) { |request| signed_by_fork?(request, 'POST', request.body) }
             .to_return(status: 200, body: captador_lead.to_json, headers: json)
      move(conversation_id: conversation.display_id, etapa_id: 3, lead_id: 'outro-lead')

      expect(stub).to have_been_requested
      expect(response).to have_http_status(:ok)
    end

    it 'repassa a recusa do Captador (409 da etapa)' do
      stub_request(:post, mover_url).to_return(status: 409, body: { codigo: 'versao' }.to_json, headers: json)
      move(conversation_id: conversation.display_id, etapa_id: 3)

      expect(response).to have_http_status(:conflict)
    end

    it 'recusa conversa que não é do Captador' do
      conversation.update!(custom_attributes: {})
      move(conversation_id: conversation.display_id, etapa_id: 3)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('not_captador_lead')
    end
  end
end
