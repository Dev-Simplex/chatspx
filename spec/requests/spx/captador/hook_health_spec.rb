require 'rails_helper'

RSpec.describe 'Captador hook health and rotation', type: :request do
  include CaptadorSigningHelpers

  let(:account) { create(:account) }
  let(:other) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:hook) { captador_hook_for(account, allowed_inbox_ids: inbox.id.to_s) }
  let(:other_hook) { captador_hook_for(other, instance_key: 'another', shared_secret: 'o' * 40) }
  let(:path) { "/api/v1/accounts/#{account.id}/integrations/hooks/#{hook.id}" }
  let(:health_url) { 'https://captador.spx.ia.br/integracao/chatspx/v1/saude' }

  before { stub_captador_dns }

  def health
    post "#{path}/process_event", params: { event: 'health' }, headers: admin.create_new_auth_token, as: :json
  end

  it 'verifies account and opaque instance key, without relaying remote secrets' do
    other_hook
    body = { account_id: account.id, instance_key: 'inst-1', secret: 'private' }.to_json
    stub_request(:get, health_url).with(headers: { 'X-Captador-Instancia' => 'inst-1' }).to_return(status: 200, body: body)
    health
    expect(response.parsed_body).to include('status' => 'ok', 'account_id' => account.id)
    expect(response.body).not_to include('private', 'shared_secret', 'another')
    expect(response.parsed_body['effective_inboxes'].pluck('id')).to eq([inbox.id])
  end

  it 'never treats a response for another account as healthy' do
    stub_request(:get, health_url).to_return(status: 200, body: { account_id: other.id, instance_key: 'inst-1' }.to_json)
    health
    expect(response.parsed_body['status']).to eq('unavailable')
  end

  it 'rejects an incorrect instance key even when the account ID matches' do
    stub_request(:get, health_url).to_return(status: 200, body: { account_id: account.id, instance_key: 'another' }.to_json)
    health
    expect(response.parsed_body['status']).to eq('unavailable')
  end

  it 'treats invalid JSON as unavailable without exposing it' do
    stub_request(:get, health_url).to_return(status: 200, body: 'private response')
    health
    expect(response.parsed_body['status']).to eq('unavailable')
    expect(response.body).not_to include('private response')
  end

  { 401 => 'authentication_failed', 404 => 'onboarding_required', 500 => 'unavailable' }.each do |code, status|
    it "reports actionable health for HTTP #{code}" do
      stub_request(:get, health_url).to_return(status: code, body: 'private response')
      health
      expect(response.parsed_body['status']).to eq(status)
      expect(response.body).not_to include('private response')
    end
  end

  it 'reports timeouts safely' do
    stub_request(:get, health_url).to_timeout
    health
    expect(response.parsed_body['status']).to eq('unavailable')
  end

  it 'reports degraded inboxes and recovers after write access is restored' do
    stub_request(:get, health_url).to_return(status: 200, body: { account_id: account.id, instance_key: 'inst-1' }.to_json)
    hook
    inbox.update!(read_only: true)
    health
    expect(response.parsed_body).to include('status' => 'degraded', 'unavailable_inbox_ids' => [inbox.id])
    inbox.update!(read_only: false)
    health
    expect(response.parsed_body['status']).to eq('ok')
  end

  it 'reports disabled hooks without calling Captador' do
    hook.update!(status: :disabled)
    health
    expect(response.parsed_body['status']).to eq('disabled')
    expect(WebMock).not_to have_requested(:get, health_url)
  end

  it 'rejects foreign inbox changes and preserves the secret and allowed list' do
    foreign = create(:channel_api, account: other).inbox
    patch path, params: { hook: { settings: { shared_secret: '', allowed_inbox_ids: foreign.id.to_s } } },
                headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(hook.reload.settings['allowed_inbox_ids']).to eq(inbox.id.to_s)
    expect(hook.captador_shared_secret).to eq('s' * 40)
  end

  it 'never accepts a supplied ciphertext as a rotation' do
    patch path, params: { hook: { settings: { shared_secret: other_hook.settings['shared_secret'] } } },
                headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(hook.reload.captador_shared_secret).to eq('s' * 40)
  end

  it 'keeps signed catalogs separate for two accounts with different keys' do
    foreign = create(:channel_api, account: other).inbox
    other_hook.update!(settings: other_hook.settings.merge('allowed_inbox_ids' => foreign.id.to_s))
    captador_get('/spx/captador/v1/catalogo', hook: hook)
    expect(response.parsed_body['inboxes'].pluck('id')).to eq([inbox.id])
    captador_get('/spx/captador/v1/catalogo', hook: other_hook)
    expect(response.parsed_body['inboxes'].pluck('id')).to eq([foreign.id])
  end

  it 'does not allow testing or editing the hook of another account' do
    foreign_path = "/api/v1/accounts/#{account.id}/integrations/hooks/#{other_hook.id}"
    post "#{foreign_path}/process_event", params: { event: 'health' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    patch foreign_path, params: { hook: { settings: { shared_secret: 'r' * 40 } } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(other_hook.reload.captador_shared_secret).to eq('o' * 40)
  end

  it 'restricts testing to integration administrators' do
    agent = create(:user, account: account, role: :agent)
    post "#{path}/process_event", params: { event: 'health' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(WebMock).not_to have_requested(:get, health_url)
  end

  it 'rotates without exposure and accepts only the new secret for signed catalog requests' do
    patch path, params: { hook: { settings: { shared_secret: 'r' * 40, shared_secret_configured: true } } },
                headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['settings']).not_to have_key('shared_secret')
    expect(response.body).not_to include('r' * 40, 'encrypted:v1:')
    expect(hook.reload.settings['allowed_inbox_ids']).to eq(inbox.id.to_s)
    captador_get('/spx/captador/v1/catalogo', hook: hook.reload, secret: 's' * 40)
    expect(response).to have_http_status(:unauthorized)
    captador_get('/spx/captador/v1/catalogo', hook: hook)
    expect(response).to have_http_status(:ok)
    captador_get('/spx/captador/v1/catalogo', hook: other_hook, secret: 'r' * 40)
    expect(response).to have_http_status(:unauthorized)
  end
end
