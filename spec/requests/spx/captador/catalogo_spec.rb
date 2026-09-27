require 'rails_helper'

# Catálogo do formulário de envio do Captador (22 §1.6): caixas oficiais e não oficiais, modelos
# aprovados, times e agentes, sem nenhuma credencial.
RSpec.describe 'Spx::Captador::Catalogo', type: :request do
  include CaptadorSigningHelpers

  let(:path) { '/spx/captador/v1/catalogo' }
  let(:account) { create(:account) }
  let(:templates) do
    [
      { 'name' => 'prospeccao_b2b_v1', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
        'namespace' => 'ns-secreto', 'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}' }] },
      { 'name' => 'aguardando', 'language' => 'pt_BR', 'status' => 'PENDING', 'category' => 'MARKETING', 'components' => [] }
    ]
  end
  let!(:cloud) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', message_templates: templates,
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let!(:waha) { create(:channel_api, account: account).inbox.tap { |inbox| inbox.update!(waha_session_name: 'comercial') } }
  let!(:widget) { create(:inbox, account: account) }
  let!(:hook) { captador_hook_for(account, allowed_inbox_ids: cloud.id.to_s) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:team) { create(:team, account: account, name: 'Comercial') }

  before { create(:inbox_member, inbox: waha, user: agent) }

  it 'lista as caixas de WhatsApp com tipo, liberação e só os modelos aprovados' do
    captador_get(path, hook: hook)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['account']).to eq('id' => account.id, 'name' => account.name)
    expect(body['inboxes'].pluck('id')).to eq([cloud.id, waha.id])

    official, unofficial = body['inboxes']
    expect(official).to include('official' => true, 'provider' => 'whatsapp_cloud', 'allowed' => true, 'read_only' => false,
                                'phone_number' => cloud.channel.phone_number)
    expect(official['templates']).to eq([{ 'name' => 'prospeccao_b2b_v1', 'language' => 'pt_BR', 'category' => 'MARKETING',
                                           'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}' }] }])
    expect(unofficial).to include('official' => false, 'provider' => 'waha', 'allowed' => false, 'phone_number' => nil, 'templates' => [])
  end

  it 'não expõe credencial de caixa nenhuma' do
    captador_get(path, hook: hook)

    expect(response.body).not_to include('provider_config', 'api_key', 'hmac_token', 'ns-secreto', 'webhook_url')
  end

  it 'lista times e agentes com as caixas por onde cada um pode enviar' do
    captador_get(path, hook: hook)

    body = response.parsed_body
    expect(body['teams']).to eq([{ 'id' => team.id, 'name' => team.name }])
    agents = body['agents'].index_by { |agent_json| agent_json['id'] }
    expect(agents[admin.id]).to include('role' => 'administrator', 'email' => admin.email, 'inbox_ids' => [cloud.id, waha.id])
    expect(agents[agent.id]).to include('role' => 'agent', 'inbox_ids' => [waha.id])
  end

  it 'exige a assinatura do Captador' do
    captador_get(path, hook: hook, secret: 'outro-segredo')

    expect(response).to have_http_status(:unauthorized)
  end
end
