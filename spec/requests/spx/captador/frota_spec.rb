require 'rails_helper'

# Frota (docs/contratos/captador.md, "Frota"): o Captador lista as contas da instalação e liga a
# integração numa delas com o token CAPTADOR_FROTA_TOKEN, sem sessão e sem nunca ver segredo.
RSpec.describe 'Spx::Captador::Frota', type: :request do
  include CaptadorSigningHelpers

  let(:token) { 'f' * 40 }
  let(:env) { { CAPTADOR_FROTA_TOKEN: token, FRONTEND_URL: 'https://chat.exemplo.com.br' } }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }
  let(:lista) { '/spx/captador/v1/frota/contas' }
  let(:account) { create(:account) }
  let!(:oficial) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let!(:waha) { create(:channel_api, account: account).inbox }
  let!(:widget) { create(:inbox, account: account) }
  let(:corpo) do
    { captador_url: 'https://captador.spx.ia.br', instance_key: 'inst-frota', shared_secret: 'z' * 40,
      allowed_inbox_ids: [waha.id], allow_login: true }
  end

  around { |example| with_modified_env(env) { example.run } }

  def ativar(conta_id, body, cabecalhos = headers)
    post "/spx/captador/v1/frota/contas/#{conta_id}/ativar", params: body.to_json,
                                                              headers: cabecalhos.merge('CONTENT_TYPE' => 'application/json')
  end

  def hook_captador
    account.hooks.find_by(app_id: 'captador')
  end

  context 'sem CAPTADOR_FROTA_TOKEN' do
    let(:env) { { CAPTADOR_FROTA_TOKEN: nil } }

    it 'responde 404 nas duas rotas, como se não existissem' do
      get lista, headers: headers
      expect(response).to have_http_status(:not_found)

      ativar(account.id, corpo)
      expect(response).to have_http_status(:not_found)
      expect(hook_captador).to be_nil
    end
  end

  context 'com token curto demais' do
    let(:token) { 'f' * 31 }

    it 'trata como desligado (404)' do
      get lista, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'responde 401 sem corpo para token errado ou ausente' do
    get lista, headers: { 'Authorization' => "Bearer #{'g' * 40}" }
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).to be_empty

    get lista
    expect(response).to have_http_status(:unauthorized)

    ativar(account.id, corpo, { 'Authorization' => token })
    expect(response).to have_http_status(:unauthorized)
    expect(hook_captador).to be_nil
  end

  it 'lista todas as contas em ordem de id, com caixas, admins e o hook, sem segredo' do
    hook = captador_hook_for(account, allowed_inbox_ids: waha.id.to_s, allow_login: true)
    admin = create(:user, account: account, role: :administrator)
    create(:user, account: account, role: :agent)
    outra = create(:account)

    get lista, headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['servidor']).to eq('chat.exemplo.com.br')
    expect(body['contas'].pluck('id')).to eq(Account.order(:id).pluck(:id))

    contas = body['contas'].index_by { |conta| conta['id'] }
    expect(contas[account.id]).to include('nome' => account.name, 'status' => 'active', 'usuarios' => 2,
                                          'criada_em' => account.reload.created_at.utc.iso8601,
                                          'admins' => [{ 'nome' => admin.name, 'email' => admin.email }])
    expect(contas[account.id]['caixas']).to eq([
                                                 { 'id' => oficial.id, 'nome' => oficial.name, 'canal' => 'Channel::Whatsapp' },
                                                 { 'id' => waha.id, 'nome' => waha.name, 'canal' => 'Channel::Api' },
                                                 { 'id' => widget.id, 'nome' => widget.name, 'canal' => 'Channel::WebWidget' }
                                               ])
    expect(contas[account.id]['captador']).to eq(
      'integracao_habilitada' => true,
      'hook' => { 'id' => hook.id, 'status' => 'enabled', 'captador_url' => 'https://captador.spx.ia.br',
                  'instance_key' => 'inst-1', 'allowed_inbox_ids' => [waha.id], 'allow_login' => true }
    )
    expect(contas[outra.id]['captador']).to eq('integracao_habilitada' => false, 'hook' => nil)
    expect(response.body).not_to include('s' * 40, 'encrypted:v1', 'shared_secret', hook.access_token)
  end

  it 'ativar liga a chave da conta, cria o hook habilitado e audita, sem devolver o segredo' do
    expect(account.captador_integration_enabled?).to be(false)

    expect { ativar(account.id, corpo) }.to have_enqueued_job(Crm::SetupJob)

    expect(response).to have_http_status(:ok)
    expect(account.reload.captador_integration_enabled?).to be(true)
    hook = hook_captador
    expect(hook).to be_enabled
    expect(hook.captador_shared_secret).to eq('z' * 40)
    expect(hook.settings).to include('captador_url' => 'https://captador.spx.ia.br', 'instance_key' => 'inst-frota',
                                     'allowed_inbox_ids' => waha.id.to_s, 'allow_login' => true)
    expect(response.parsed_body).to include('id' => account.id, 'nome' => account.name)
    expect(response.parsed_body['captador']).to eq(
      'integracao_habilitada' => true,
      'hook' => { 'id' => hook.id, 'status' => 'enabled', 'captador_url' => 'https://captador.spx.ia.br',
                  'instance_key' => 'inst-frota', 'allowed_inbox_ids' => [waha.id], 'allow_login' => true }
    )
    expect(response.body).not_to include('z' * 40, 'shared_secret', 'encrypted:v1')

    auditoria = Audited.audit_class.find_by(auditable_type: 'Integrations::Hook', auditable_id: hook.id, comment: 'captador.frota.ativar')
    expect(auditoria).to have_attributes(associated_id: account.id, remote_address: '127.0.0.1')
    expect(auditoria.audited_changes.to_json).not_to include('z' * 40)
  end

  it 'ativar de novo atualiza o mesmo hook (idempotente) e mantém o segredo quando ele não vem' do
    hook = captador_hook_for(account, allowed_inbox_ids: oficial.id.to_s)
    hook.update!(status: 'disabled')
    account.update!(captador_integration_enabled: false)

    ativar(account.id, corpo.merge(instance_key: 'inst-nova', shared_secret: 'n' * 40, allow_login: false))
    ativar(account.id, corpo.merge(instance_key: 'inst-nova', allow_login: false).except(:shared_secret))

    expect(response).to have_http_status(:ok)
    expect(account.hooks.where(app_id: 'captador').count).to eq(1)
    expect(account.reload.captador_integration_enabled?).to be(true)
    expect(hook.reload).to be_enabled
    expect(hook.settings).to include('instance_key' => 'inst-nova', 'allowed_inbox_ids' => waha.id.to_s, 'allow_login' => false)
    expect(hook.captador_shared_secret).to eq('n' * 40)
  end

  it '"todas" libera todas as caixas de WhatsApp e API da conta' do
    ativar(account.id, corpo.merge(allowed_inbox_ids: 'todas'))

    expect(response).to have_http_status(:ok)
    expect(hook_captador.settings['allowed_inbox_ids']).to eq("#{oficial.id},#{waha.id}")
    expect(response.parsed_body.dig('captador', 'hook', 'allowed_inbox_ids')).to eq([oficial.id, waha.id])
  end

  it 'responde 404 para conta inexistente' do
    ativar(Account.maximum(:id).to_i + 1, corpo)

    expect(response).to have_http_status(:not_found)
  end

  it 'recusa configuração inválida com 422 e não grava nada' do
    caixa_de_outra_conta = create(:channel_api, account: create(:account)).inbox
    invalidos = [
      corpo.merge(shared_secret: 'curto'),
      corpo.merge(captador_url: 'http://captador.spx.ia.br'),
      corpo.merge(instance_key: 'com espaço'),
      corpo.merge(allow_login: 'sim'),
      corpo.merge(allowed_inbox_ids: [caixa_de_outra_conta.id]),
      corpo.merge(allowed_inbox_ids: [widget.id]),
      corpo.merge(allowed_inbox_ids: waha.id.to_s),
      corpo.merge(shared_secret: "encrypted:v1:#{'x' * 40}"),
      corpo.except(:shared_secret)
    ]

    invalidos.each do |body|
      ativar(account.id, body)
      expect(response).to have_http_status(:unprocessable_entity), "esperava 422 para #{body.except(:shared_secret)}"
      expect(response.parsed_body['error_code']).to eq('configuracao_invalida')
      expect(response.parsed_body.dig('meta', 'erros')).to be_present
    end
    expect(account.reload.captador_integration_enabled?).to be(false)
    expect(hook_captador).to be_nil
  end
end
