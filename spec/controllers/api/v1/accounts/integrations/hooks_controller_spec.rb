require 'rails_helper'

RSpec.describe 'Integration Hooks API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:params) { { app_id: 'dialogflow', inbox_id: inbox.id, settings: { project_id: 'xx', credentials: { test: 'test' }, region: 'europe-west1' } } }

  describe 'POST /api/v1/accounts/{account.id}/integrations/hooks' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_integrations_hooks_url(account_id: account.id),
             params: params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'return unauthorized if agent' do
        post api_v1_account_integrations_hooks_url(account_id: account.id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates hooks if admin' do
        post api_v1_account_integrations_hooks_url(account_id: account.id),
             params: params,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        data = response.parsed_body
        expect(data['app_id']).to eq params[:app_id]
      end

      it 'validates Cloudflare RealtimeKit credentials before creating the hook' do
        allow(Integrations::Cloudflare::RealtimeKitCredentialsValidator).to receive(:validate)
          .and_return(Integrations::Cloudflare::RealtimeKitCredentialsValidator::Result.new(false, :invalid_api_token))

        post api_v1_account_integrations_hooks_url(account_id: account.id),
             params: { app_id: 'dyte', settings: { account_id: 'bad', app_id: 'bad', api_token: 'bad' } },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include(I18n.t('errors.cloudflare.realtimekit.invalid_api_token'))
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/integrations/hooks/{hook_id}' do
    let(:hook) { create(:integrations_hook, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
              params: params,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'return unauthorized if agent' do
        patch api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
              params: params,
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates hook if admin' do
        patch api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
              params: params,
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        data = response.parsed_body
        expect(data['app_id']).to eq 'slack'
      end

      # ChatSPX (item 26) — ACEITE: a credencial existente SOBREVIVE a um update que não a mencione.
      #
      # Defeito de composição, e nenhum dos três lados está errado sozinho — por isso passava por
      # toda a suíte verde:
      #   1. o upstream passou a filtrar `settings` por `app.visible_properties` no
      #      `_hook.json.jbuilder` (isolado, isso é MAIS seguro: não devolve segredo no JSON);
      #   2. o nosso `EditHook.vue` (arquivo 100% do fork — o upstream não tem tela de editar hook)
      #      lê o hash já filtrado, grava '' no campo que veio `undefined` e reenvia tudo;
      #   3. `HooksController#update` SOBRESCREVIA o jsonb inteiro.
      # Resultado: abrir "Editar" e salvar destruía a credencial no banco. 200 OK, sem log.
      # São 6 integrações e 14 chaves. Exposição medida nesta VM: 1 hook openai habilitado.
      context 'when updating a hook whose credential the server does not return' do
        let!(:openai_hook) do
          create(:integrations_hook, :openai, account: account,
                                              settings: { 'api_key' => 'sk-original', 'label_suggestion' => false })
        end

        before do
          # `validate_openai_api_key` faz HTTP síncrono dentro do save quando a api_key MUDA.
          # Aqui o que está sob teste é a PERDA DO DADO, não a validação — stubar mantém o
          # exemplo determinístico e sem rede. É também a prova da cadeia entre os dois defeitos:
          # sem a correção a chave mudaria para '', e é essa mudança que arma o job do item 8.
          allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
        end

        it 'does not return the api_key in the payload' do
          # Guarda de regressão: o filtro do upstream é a parte CERTA e NÃO pode ser desfeita.
          # Desfazê-la trocaria perda de dado por vazamento de segredo.
          get api_v1_account_integrations_apps_url(account_id: account.id),
              headers: admin.create_new_auth_token,
              as: :json

          hook_payload = response.parsed_body['payload'].find { |app| app['id'] == 'openai' }['hooks'].first
          expect(hook_payload['settings']).to eq('label_suggestion' => false)
        end

        it 'keeps the stored api_key when the update does not mention it' do
          # Exatamente o payload que `EditHook.vue` produz depois da correção do front: a chave que
          # o servidor não devolveu não é reenviada.
          patch api_v1_account_integrations_hook_url(account_id: account.id, id: openai_hook.id),
                params: { hook: { settings: { label_suggestion: true } } },
                headers: admin.create_new_auth_token,
                as: :json

          expect(response).to have_http_status(:success)
          expect(openai_hook.reload.settings).to eq('api_key' => 'sk-original', 'label_suggestion' => true)
        end

        it 'keeps the stored api_key even when a client blanks it out' do
          # O front corrigido não manda mais '', mas um script que chame a API direto — ou uma tela
          # futura — ainda pode. É por isso que o merge no servidor é necessário além do front:
          # cada lado fecha um caminho diferente.
          patch api_v1_account_integrations_hook_url(account_id: account.id, id: openai_hook.id),
                params: { hook: { settings: { api_key: '', label_suggestion: true } } },
                headers: admin.create_new_auth_token,
                as: :json

          expect(response).to have_http_status(:success)
          expect(openai_hook.reload.settings['api_key']).to eq('sk-original')
        end

        it 'still lets an administrator replace the credential on purpose' do
          # O merge não pode virar prisão: trocar a chave de propósito continua funcionando.
          patch api_v1_account_integrations_hook_url(account_id: account.id, id: openai_hook.id),
                params: { hook: { settings: { api_key: 'sk-nova' } } },
                headers: admin.create_new_auth_token,
                as: :json

          expect(response).to have_http_status(:success)
          expect(openai_hook.reload.settings['api_key']).to eq('sk-nova')
        end
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/integrations/hooks/{hook_id}/process_event' do
    let(:hook) { create(:integrations_hook, account: account) }
    let(:params) { { event: 'rephrase', payload: { test: 'test' } } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post process_event_api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
             params: params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'will process the events' do
        post process_event_api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq 'No processor found'
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/integrations/hooks/{hook_id}' do
    let(:hook) { create(:integrations_hook, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'return unauthorized if agent' do
        delete api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates hook if admin' do
        delete api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
               headers: admin.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Integrations::Hook.exists?(hook.id)).to be false
      end
    end
  end
end
