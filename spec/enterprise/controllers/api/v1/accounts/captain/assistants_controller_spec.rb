require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Assistants', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/assistants' do
    context 'when it is an un-authenticated user' do
      it 'does not fetch assistants' do
        get "/api/v1/accounts/#{account.id}/captain/assistants",
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'fetches assistants for the account' do
        create_list(:captain_assistant, 3, account: account)
        get "/api/v1/accounts/#{account.id}/captain/assistants",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:payload].length).to eq(3)
        expect(json_response[:meta]).to eq(
          { total_count: 3, page: 1 }
        )
      end

      it 'includes avatar_url, agent_bot_id (mirror) and inbox_ids in the payload' do
        assistant = create(:captain_assistant, account: account)
        inbox = create(:inbox, account: account)
        create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
        mirror = assistant.mirror_agent_bot

        get "/api/v1/accounts/#{account.id}/captain/assistants",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        payload = json_response[:payload].find { |item| item[:id] == assistant.id }
        expect(payload).to have_key(:avatar_url)
        expect(payload[:avatar_url]).to eq(assistant.avatar_url)
        expect(payload[:agent_bot_id]).to eq(mirror.id)
        expect(payload[:inbox_ids]).to eq([inbox.id])
      end

      it 'returns nil agent_bot_id without creating a mirror when it is missing' do
        assistant = create(:captain_assistant, account: account)
        assistant.agent_bot&.destroy!

        expect do
          get "/api/v1/accounts/#{account.id}/captain/assistants",
              headers: agent.create_new_auth_token,
              as: :json
        end.not_to change(AgentBot, :count)

        expect(response).to have_http_status(:success)
        payload = json_response[:payload].find { |item| item[:id] == assistant.id }
        expect(payload[:agent_bot_id]).to be_nil
        expect(payload[:inbox_ids]).to eq([])
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/assistants/{id}' do
    let(:assistant) { create(:captain_assistant, account: account) }

    context 'when it is an un-authenticated user' do
      it 'does not fetch the assistant' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'fetches the assistant' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:id]).to eq(assistant.id)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/captain/assistants' do
    let(:valid_attributes) do
      {
        assistant: {
          name: 'New Assistant',
          description: 'Assistant Description',
          response_guidelines: ['Be helpful', 'Be concise'],
          guardrails: ['No harmful content', 'Stay on topic'],
          config: {
            product_name: 'Chatwoot',
            feature_faq: true,
            feature_memory: false,
            feature_citation: true
          }
        }
      }
    end

    context 'when it is an un-authenticated user' do
      it 'does not create an assistant' do
        post "/api/v1/accounts/#{account.id}/captain/assistants",
             params: valid_attributes,
             as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'does not create an assistant' do
        post "/api/v1/accounts/#{account.id}/captain/assistants",
             params: valid_attributes,
             headers: agent.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin' do
      it 'creates a new assistant' do
        expect do
          post "/api/v1/accounts/#{account.id}/captain/assistants",
               params: valid_attributes,
               headers: admin.create_new_auth_token,
               as: :json
        end.to change(Captain::Assistant, :count).by(1)

        expect(json_response[:name]).to eq('New Assistant')
        expect(json_response[:response_guidelines]).to eq(['Be helpful', 'Be concise'])
        expect(json_response[:guardrails]).to eq(['No harmful content', 'Stay on topic'])
        expect(json_response[:config][:product_name]).to eq('Chatwoot')
        expect(json_response[:config][:feature_citation]).to be(true)
        expect(response).to have_http_status(:success)
      end

      it 'creates an assistant with feature_citation disabled' do
        attributes_with_disabled_citation = valid_attributes.deep_dup
        attributes_with_disabled_citation[:assistant][:config][:feature_citation] = false

        expect do
          post "/api/v1/accounts/#{account.id}/captain/assistants",
               params: attributes_with_disabled_citation,
               headers: admin.create_new_auth_token,
               as: :json
        end.to change(Captain::Assistant, :count).by(1)

        expect(json_response[:config][:feature_citation]).to be(false)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/captain/assistants/{id}' do
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:update_attributes) do
      {
        assistant: {
          name: 'Updated Assistant',
          response_guidelines: ['Updated guideline'],
          guardrails: ['Updated guardrail'],
          config: {
            feature_citation: false
          }
        }
      }
    end

    context 'when it is an un-authenticated user' do
      it 'does not update the assistant' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: update_attributes,
              as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'does not update the assistant' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: update_attributes,
              headers: agent.create_new_auth_token,
              as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin' do
      it 'updates the assistant' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: update_attributes,
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:name]).to eq('Updated Assistant')
        expect(json_response[:response_guidelines]).to eq(['Updated guideline'])
        expect(json_response[:guardrails]).to eq(['Updated guardrail'])
      end

      it 'updates only response_guidelines when only that is provided' do
        assistant.update!(response_guidelines: ['Original guideline'], guardrails: ['Original guardrail'])
        original_name = assistant.name

        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { response_guidelines: ['New guideline only'] } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:name]).to eq(original_name)
        expect(json_response[:response_guidelines]).to eq(['New guideline only'])
        expect(json_response[:guardrails]).to eq(['Original guardrail'])
      end

      it 'updates only guardrails when only that is provided' do
        assistant.update!(response_guidelines: ['Original guideline'], guardrails: ['Original guardrail'])
        original_name = assistant.name

        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { guardrails: ['New guardrail only'] } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:name]).to eq(original_name)
        expect(json_response[:response_guidelines]).to eq(['Original guideline'])
        expect(json_response[:guardrails]).to eq(['New guardrail only'])
      end

      it 'updates feature_citation config' do
        assistant.update!(config: { 'feature_citation' => true })

        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { config: { feature_citation: false } } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:config][:feature_citation]).to be(false)
      end
    end

    # Regressão: `config` é jsonb e `update!` substitui o hash inteiro. Com o strong params
    # de lista fechada, salvar um único campo pela tela apagava calado todas as chaves de
    # fora da lista (na Tozi os 8 agentes perderam `team_id`, a Clara perdeu `triage`).
    # O teste é de INVARIANTE: nenhum conjunto de chaves pode encolher num PATCH parcial.
    context 'when an admin updates a single config field' do
      # Tudo que hoje mora em captain_assistants.config em produção: o que a tela edita,
      # o que só o backend lê (team_id, triage, voice_id, fotos_carrossel*) e uma chave
      # desconhecida, que representa qualquer config futura que ninguém declarou aqui.
      let(:full_config) do
        {
          'product_name' => 'Imobiliária SPX',
          'feature_faq' => true,
          'feature_memory' => true,
          'feature_citation' => true,
          'feature_contact_attributes' => false,
          'welcome_message' => 'Olá, tudo bem?',
          'handoff_message' => 'Vou te transferir para um atendente.',
          'resolution_message' => 'Posso ajudar em mais alguma coisa?',
          'instructions' => 'Instrução original',
          'temperature' => 0.7,
          'knowledge_mode' => 'hybrid',
          'contextual_chunks' => 5,
          'tools' => %w[buscar_imovel transferir_para_agente],
          'team_id' => 42,
          'triage' => true,
          'voice_id' => 'voz-eleven-labs-123',
          'fotos_carrossel' => true,
          'fotos_carrossel_botoes' => 'ver_detalhes',
          'chave_desconhecida' => 'valor que nenhuma tela conhece'
        }
      end

      before { assistant.update!(config: full_config) }

      it 'keeps every other config key untouched' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { config: { instructions: 'Instrução nova' } } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)

        saved_config = assistant.reload.config

        # nenhuma chave sumiu
        expect(saved_config.keys).to match_array(full_config.keys)
        # o campo editado mudou
        expect(saved_config['instructions']).to eq('Instrução nova')
        # e todo o resto continua com o MESMO valor
        expect(saved_config.except('instructions')).to eq(full_config.except('instructions'))
      end

      it 'returns the whole config in the response, not just the edited field' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { config: { instructions: 'Instrução nova' } } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:config].keys.map(&:to_s)).to match_array(full_config.keys)
      end

      it 'keeps config intact when the payload has no config at all' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { name: 'Só o nome mudou' } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(assistant.reload.config).to eq(full_config)
      end

      it 'persists the backend-only keys when the screen sends them' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: {
                assistant: {
                  config: {
                    team_id: 99, triage: false, voice_id: 'outra-voz',
                    fotos_carrossel: false, fotos_carrossel_botoes: 'quick_replies'
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)

        saved_config = assistant.reload.config

        expect(saved_config.keys).to match_array(full_config.keys)
        expect(saved_config).to include(
          'team_id' => 99,
          'triage' => false,
          'voice_id' => 'outra-voz',
          'fotos_carrossel' => false,
          'fotos_carrossel_botoes' => 'quick_replies'
        )
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/captain/assistants/{id}' do
    let!(:assistant) { create(:captain_assistant, account: account) }

    context 'when it is an un-authenticated user' do
      it 'does not delete the assistant' do
        delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
               as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'delete the assistant' do
        delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
               headers: agent.create_new_auth_token,
               as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin' do
      it 'deletes the assistant' do
        expect do
          delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end.to change(Captain::Assistant, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/captain/assistants/{id}/playground' do
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:valid_params) do
      {
        assistant: {
          message_content: 'Hello assistant',
          message_history: [
            { role: 'user', content: 'Previous message' },
            { role: 'assistant', content: 'Previous response', agent_name: 'billing_scenario' }
          ]
        }
      }
    end
    let(:chat_service) { instance_double(Captain::Llm::AssistantChatService) }
    let(:agent_runner_service) { instance_double(Captain::Assistant::AgentRunnerService) }

    before do
      hook_service = instance_double(Captain::OpenaiHookService, configured?: true)
      allow(Captain::OpenaiHookService).to receive(:new).and_return(hook_service)
    end

    context 'when it is an un-authenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when captain v2 is disabled' do
      it 'generates a response with the legacy assistant chat service' do
        allow(Captain::Llm::AssistantChatService).to receive(:new).with(
          assistant: assistant,
          source: 'playground'
        ).and_return(chat_service)
        allow(chat_service).to receive(:generate_response).and_return({ content: 'Assistant response' })
        expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: valid_params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(chat_service).to have_received(:generate_response).with(
          additional_message: valid_params[:assistant][:message_content],
          message_history: valid_params[:assistant][:message_history]
        )
        expect(json_response[:content]).to eq('Assistant response')
      end

      it 'uses empty array as default' do
        params_without_history = { assistant: { message_content: 'Hello assistant' } }
        allow(Captain::Llm::AssistantChatService).to receive(:new).with(
          assistant: assistant,
          source: 'playground'
        ).and_return(chat_service)
        allow(chat_service).to receive(:generate_response).and_return({ content: 'Assistant response' })
        expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: params_without_history,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(chat_service).to have_received(:generate_response).with(
          additional_message: params_without_history[:assistant][:message_content],
          message_history: []
        )
      end
    end

    context 'when captain v2 is enabled' do
      before do
        account.enable_features('captain_integration_v2')
      end

      it 'generates a response with the agent runner service' do
        allow(Captain::Assistant::AgentRunnerService).to receive(:new).with(
          assistant: assistant,
          source: 'playground'
        ).and_return(agent_runner_service)
        allow(agent_runner_service).to receive(:generate_response).and_return({ response: 'Assistant response' })
        expect(Captain::Llm::AssistantChatService).not_to receive(:new)

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: valid_params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(agent_runner_service).to have_received(:generate_response).with(
          message_history: valid_params[:assistant][:message_history] + [{ role: 'user', content: valid_params[:assistant][:message_content] }]
        )
        expect(json_response[:response]).to eq('Assistant response')
      end

      it 'does not duplicate the latest user message if it is already in history' do
        params_with_latest_message = {
          assistant: {
            message_content: 'Hello assistant',
            message_history: [{ role: 'user', content: 'Hello assistant' }]
          }
        }
        allow(Captain::Assistant::AgentRunnerService).to receive(:new).with(
          assistant: assistant,
          source: 'playground'
        ).and_return(agent_runner_service)
        allow(agent_runner_service).to receive(:generate_response).and_return({ response: 'Assistant response' })

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: params_with_latest_message,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(agent_runner_service).to have_received(:generate_response).with(
          message_history: params_with_latest_message[:assistant][:message_history]
        )
      end
    end
  end
end
