require 'rails_helper'

RSpec.describe 'Inbox Tracking Credentials API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:secret) { 'EAAmeta-access-token-que-nao-pode-vazar-9876' }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_credential" }

  describe 'GET /api/v1/accounts/{account_id}/inboxes/{inbox_id}/tracking_credential' do
    it 'returns unauthorized for an unauthenticated user' do
      get base_url

      expect(response).to have_http_status(:unauthorized)
      # Esta base responde 401 tanto para "nao entrou" quanto para "entrou e o Pundit negou". So o
      # status nao distingue os dois casos, e um teste que so olhasse o status passaria mesmo se a
      # policy nunca fosse consultada. O CORPO distingue: aqui vem a chave `errors` do Devise...
      expect(response.parsed_body).to have_key('errors')
    end

    it 'denies an agent: tracking secrets are admin-only' do
      get base_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      # ...e aqui, a chave `error` do Pundit — prova de que a negacao veio da policy.
      expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
    end

    context 'when the inbox has a credential' do
      let!(:credential) do
        create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret, meta_test_event_code: 'TEST42')
      end

      # ESTE e o aceite do bloco 5.02, e a primeira expectativa e o CONTROLE dele: sem provar que o
      # segredo esta de fato gravado e legivel, o `not_to include` abaixo passaria tambem num mundo
      # em que o campo nunca existiu — mediria nada.
      it 'never returns the secret in plain text' do
        expect(credential.reload.meta_access_token).to eq(secret)

        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include(secret)
        expect(response.parsed_body.to_s).not_to include(secret)
      end

      it 'returns only `configured` and the last four characters' do
        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['meta_access_token']).to eq('configured' => true, 'last_four' => '9876')
        expect(response.parsed_body['ga4_api_secret']).to eq('configured' => true, 'last_four' => '0002')
        expect(response.parsed_body['google_ads_refresh_token']).to eq('configured' => false, 'last_four' => nil)
      end

      it 'returns the non-secret fields as they are' do
        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['meta_test_event_code']).to eq('TEST42')
      end
    end

    it 'returns an unconfigured credential when the inbox has none yet' do
      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta_access_token']).to eq('configured' => false, 'last_four' => nil)
    end

    it 'returns not found for an inbox of another account' do
      other_inbox = create(:inbox, account: create(:account))

      get "/api/v1/accounts/#{account.id}/inboxes/#{other_inbox.id}/tracking_credential",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/accounts/{account_id}/inboxes/{inbox_id}/tracking_credential' do
    it 'denies an agent' do
      patch base_url, params: { tracking_credential: { meta_access_token: secret } },
                      headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
      expect(TrackingCredential.find_by(inbox: inbox)).to be_nil
    end

    it 'stores the secret without echoing it back' do
      patch base_url, params: { tracking_credential: { meta_access_token: secret } },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(TrackingCredential.find_by(inbox: inbox).meta_access_token).to eq(secret)
      expect(response.body).not_to include(secret)
    end

    # A perda silenciosa que esta base ja sofreu em `Integrations::Hook`: a tela nunca recebe o
    # valor, o formulario reenvia `''` e o `update!` apagava a credencial com 200 OK. Sem a guarda
    # do controller este teste fica vermelho.
    it 'does not wipe a stored secret when the client sends an empty string' do
      create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret)

      patch base_url, params: { tracking_credential: { meta_access_token: '', meta_test_event_code: 'TEST99' } },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      credential = TrackingCredential.find_by(inbox: inbox)
      expect(credential.meta_access_token).to eq(secret)
      expect(credential.meta_test_event_code).to eq('TEST99')
    end

    it 'replaces a stored secret when a new value arrives' do
      create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret)

      patch base_url, params: { tracking_credential: { meta_access_token: 'EAAtoken-novo-4321' } },
                      headers: admin.create_new_auth_token, as: :json

      expect(TrackingCredential.find_by(inbox: inbox).meta_access_token).to eq('EAAtoken-novo-4321')
    end
  end

  describe 'POST /api/v1/accounts/{account_id}/inboxes/{inbox_id}/tracking_credential/verify' do
    let!(:credential) { create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret) }
    let(:verifier) { instance_double(TrackingCredentials::Verifier) }

    before { allow(TrackingCredentials::Verifier).to receive(:new).and_return(verifier) }

    it 'denies an agent' do
      post "#{base_url}/verify", params: { provider: 'meta' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
    end

    it 'returns the verification result' do
      allow(verifier).to receive(:perform).and_return({ success: true, provider: 'meta', message: 'ok' })

      post "#{base_url}/verify", params: { provider: 'meta' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['success']).to be(true)
      expect(TrackingCredentials::Verifier).to have_received(:new).with(anything, provider: 'meta')
    end

    it 'returns unprocessable entity when the provider rejects the credential' do
      allow(verifier).to receive(:perform).and_return({ success: false, provider: 'meta', message: 'recusado' })

      post "#{base_url}/verify", params: { provider: 'meta' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('recusado')
    end

    it 'never leaks the secret in the verification response' do
      # Controle: o segredo existe e esta legivel — sem isto, o `not_to include` abaixo mediria nada.
      expect(credential.reload.meta_access_token).to eq(secret)
      allow(verifier).to receive(:perform).and_return({ success: true, provider: 'meta', message: 'ok' })

      post "#{base_url}/verify", params: { provider: 'meta' }, headers: admin.create_new_auth_token, as: :json

      expect(response.body).not_to include(secret)
    end
  end
end
