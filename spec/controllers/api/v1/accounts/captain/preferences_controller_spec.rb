# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Preferences', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/preferences' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns captain config' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        expect(json_response).to have_key(:llm_connection)
        expect(json_response[:llm_connection][:provider]).to eq('openai')
        expect(json_response[:llm_connection][:configured]).to be(false)
      end
    end

    context 'when it is an admin' do
      it 'returns captain config' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        expect(json_response).to have_key(:llm_connection)
      end

      it 'returns gpt-5-mini as default for assistant and copilot' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response.dig(:features, :assistant, :default)).to eq('gpt-5-mini')
        expect(json_response.dig(:features, :copilot, :default)).to eq('gpt-5-mini')
      end

      it 'shows audio transcription as on when only the real gate is on' do
        account.update!(audio_transcriptions: true)

        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response.dig(:features, :audio_transcription, :enabled)).to be(true)
      end

      it 'shows label suggestion as on for an account that never touched the toggle' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response.dig(:features, :label_suggestion, :enabled)).to be(true)
      end

      it 'returns llm_connection details when hook is configured' do
        create(
          :integrations_hook,
          :openai,
          account: account,
          settings: { api_key: 'sk-test-key-1234' }
        )

        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:llm_connection][:configured]).to be(true)
        expect(json_response[:llm_connection][:masked_api_key]).to start_with('sk-t')
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/captain/preferences' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            params: { captain_models: { editor: 'gpt-4.1-mini' } },
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns forbidden' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: agent.create_new_auth_token,
            params: { captain_models: { editor: 'gpt-4.1-mini' } },
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin' do
      it 'updates captain_models' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_models: { editor: 'gpt-4.1-mini' } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        expect(account.reload.captain_models['editor']).to eq('gpt-4.1-mini')
      end

      it 'updates captain_features' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_features: { editor: true } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        expect(account.reload.captain_features['editor']).to be true
      end

      it 'writes the audio transcription toggle to the gate the code respects' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_features: { audio_transcription: true } },
            as: :json

        expect(response).to have_http_status(:success)
        account.reload
        expect(account.audio_transcriptions).to be true
        expect(account.captain_features).not_to have_key('audio_transcription')
        expect(json_response.dig(:features, :audio_transcription, :enabled)).to be(true)
      end

      it 'turns the audio transcription off through the same gate' do
        account.update!(audio_transcriptions: true)

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_features: { audio_transcription: false } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.audio_transcriptions).to be false
        expect(json_response.dig(:features, :audio_transcription, :enabled)).to be(false)
      end

      it 'turns label suggestion off when the admin asks for it' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_features: { label_suggestion: false } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.captain_features['label_suggestion']).to be false
        expect(json_response.dig(:features, :label_suggestion, :enabled)).to be(false)
      end

      it 'merges with existing captain_models' do
        account.update!(captain_models: { 'editor' => 'gpt-4.1-mini', 'assistant' => 'gpt-5' })

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_models: { editor: 'gpt-4.1' } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        models = account.reload.captain_models
        expect(models['editor']).to eq('gpt-4.1')
        expect(models['assistant']).to eq('gpt-5') # Preserved
      end

      it 'merges with existing captain_features' do
        account.update!(captain_features: { 'editor' => true, 'assistant' => false })

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_features: { editor: false } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        features = account.reload.captain_features
        expect(features['editor']).to be false
        expect(features['assistant']).to be false # Preserved
      end

      it 'updates both models and features in single request' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: {
              captain_models: { editor: 'gpt-4.1-mini' },
              captain_features: { editor: true }
            },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        account.reload
        expect(account.captain_models['editor']).to eq('gpt-4.1-mini')
        expect(account.captain_features['editor']).to be true
      end

      it 'creates or updates account OpenAI key via llm_connection payload' do
        allow_any_instance_of(Captain::OpenaiHookService)
          .to receive(:validate_api_key!)
          .and_return(true)

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: {
              llm_connection: {
                openai_api_key: 'sk-account-key-9876'
              }
            },
            as: :json

        expect(response).to have_http_status(:success)
        hook = account.reload.hooks.find_by(app_id: 'openai')
        expect(hook).to be_present
        expect(hook.settings['api_key']).to eq('sk-account-key-9876')
        expect(json_response[:llm_connection][:configured]).to be(true)
      end

      it 'returns validation error when OpenAI key is invalid' do
        allow_any_instance_of(Captain::OpenaiHookService)
          .to receive(:validate_and_upsert_api_key!)
          .and_raise(
            Captain::OpenaiHookService::InvalidApiKeyError,
            I18n.t('captain.errors.invalid_api_key')
          )

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: {
              llm_connection: {
                openai_api_key: 'sk-invalid-key'
              }
            },
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response[:code]).to eq('captain_api_key_invalid')
        expect(json_response[:message]).to eq(I18n.t('captain.errors.invalid_api_key'))
        expect(account.reload.hooks.find_by(app_id: 'openai')).to be_nil
      end

      it 'returns validation unavailable error when provider cannot be reached' do
        allow_any_instance_of(Captain::OpenaiHookService)
          .to receive(:validate_and_upsert_api_key!)
          .and_raise(
            Captain::OpenaiHookService::ApiConnectionError,
            I18n.t('captain.errors.api_key_validation_failed')
          )

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: {
              llm_connection: {
                openai_api_key: 'sk-any-key'
              }
            },
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response[:code]).to eq('captain_api_key_validation_failed')
        expect(json_response[:message]).to eq(I18n.t('captain.errors.api_key_validation_failed'))
        expect(account.reload.hooks.find_by(app_id: 'openai')).to be_nil
      end

      it 'removes account OpenAI key via llm_connection payload' do
        create(
          :integrations_hook,
          :openai,
          account: account,
          settings: { api_key: 'sk-remove-me-1234' }
        )

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: {
              llm_connection: {
                remove_api_key: true
              }
            },
            as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.hooks.find_by(app_id: 'openai')).to be_nil
        expect(json_response[:llm_connection][:configured]).to be(false)
      end
    end
  end
end
