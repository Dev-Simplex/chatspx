require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::CopilotThreads', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:openai_hook) do
    create(:integrations_hook, :openai, account: account, settings: { api_key: 'test-key' })
  end
  let(:conversation) { create(:conversation, account: account) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/copilot_threads' do
    context 'when it is an un-authenticated user' do
      it 'does not fetch copilot threads' do
        get "/api/v1/accounts/#{account.id}/captain/copilot_threads",
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'fetches copilot threads for the current user' do
        # Create threads for the current agent
        create_list(:captain_copilot_thread, 3, account: account, user: agent)
        # Create threads for another user (should not be included)
        create_list(:captain_copilot_thread, 2, account: account, user: admin)

        get "/api/v1/accounts/#{account.id}/captain/copilot_threads",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:payload].length).to eq(3)

        expect(json_response[:payload].map { |thread| thread[:user][:id] }.uniq).to eq([agent.id])
      end

      it 'returns threads in descending order of creation' do
        threads = create_list(:captain_copilot_thread, 3, account: account, user: agent)

        get "/api/v1/accounts/#{account.id}/captain/copilot_threads",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:payload].pluck(:id)).to eq(threads.reverse.pluck(:id))
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/captain/copilot_threads' do
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:valid_params) { { message: 'Hello, how can you help me?', assistant_id: assistant.id, conversation_id: conversation.display_id } }

    context 'when it is an un-authenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      context 'with invalid params' do
        it 'returns error when message is blank' do
          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: { message: '', assistant_id: assistant.id },
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_response[:error]).to eq('Message is required')
        end

        it 'returns error when assistant_id is invalid' do
          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: { message: 'Hello', assistant_id: 0 },
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:not_found)
        end
      end

      context 'with valid params' do
        # O painel V2 cria a thread e gera a resposta pelo endpoint de streaming.
        # Sem skip_response o job legado geraria uma SEGUNDA resposta.
        it 'does not enqueue the legacy response job when skip_response is set' do
          expect do
            post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
                 params: valid_params.merge(skip_response: true),
                 headers: agent.create_new_auth_token,
                 as: :json
          end.not_to have_enqueued_job(Captain::Copilot::ResponseJob)

          expect(response).to have_http_status(:success)
          expect(CopilotThread.last.copilot_messages.pluck(:message_type)).to eq(['user'])
        end

        it 'enqueues the legacy response job by default' do
          expect do
            post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
                 params: valid_params,
                 headers: agent.create_new_auth_token,
                 as: :json
          end.to have_enqueued_job(Captain::Copilot::ResponseJob)
        end

        it 'returns error when usage limit is exceeded' do
          account.limits = { captain_responses: 2 }
          account.custom_attributes = { captain_responses_usage: 2 }
          account.save!

          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: valid_params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          expect(CopilotMessage.last.message['content']).to eq(
            'You are out of Copilot credits. You can buy more credits from the billing section.'
          )
        end

        it 'creates a new copilot thread with initial message' do
          account.limits = { captain_responses: 2 }
          account.custom_attributes = { captain_responses_usage: 0 }
          account.save!

          expect do
            post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
                 params: valid_params,
                 headers: agent.create_new_auth_token,
                 as: :json
          end.to change(CopilotThread, :count).by(1)
             .and change(CopilotMessage, :count).by(1)

          expect(response).to have_http_status(:success)

          thread = CopilotThread.last
          expect(thread.title).to eq(valid_params[:message])
          expect(thread.user_id).to eq(agent.id)
          expect(thread.assistant_id).to eq(assistant.id)

          message = thread.copilot_messages.last
          expect(message.message).to eq({ 'content' => valid_params[:message] })

          expect(Captain::Copilot::ResponseJob).to have_been_enqueued.with(
            assistant: assistant,
            conversation_id: valid_params[:conversation_id],
            user_id: agent.id,
            copilot_thread_id: thread.id,
            copilot_message_id: message.id,
            message: valid_params[:message]
          )
        end
      end

      context 'when account OpenAI key is missing' do
        before do
          openai_hook.destroy!
        end

        it 'returns a standardized missing key error' do
          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: valid_params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_response[:code]).to eq('captain_api_key_missing')
          expect(json_response[:message]).to eq(
            I18n.t('captain.errors.missing_api_key', locale: account.locale.to_sym)
          )
        end
      end
    end
  end
end
