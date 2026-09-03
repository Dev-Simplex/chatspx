require 'rails_helper'

RSpec.describe 'Conversation Assignment API', type: :request do
  let(:account) { create(:account) }

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/assignments' do
    let(:conversation) { create(:conversation, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated bot with out access to the inbox' do
      let(:agent_bot) { create(:agent_bot) }
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
             headers: { api_access_token: agent_bot.access_token.token },
             params: {
               assignee_id: agent.id
             },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to the inbox' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:agent_bot) { create(:agent_bot, account: account) }
      let(:team) { create(:team, account: account) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'assigns a user to the conversation' do
        params = { assignee_id: agent.id }

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.assignee).to eq(agent)
      end

      it 'assigns an agent bot to the conversation' do
        params = { assignee_id: agent_bot.id, assignee_type: 'AgentBot' }

        expect(Conversations::AssignmentService).to receive(:new)
          .with(hash_including(conversation: conversation, assignee_id: agent_bot.id, assignee_type: 'AgentBot'))
          .and_call_original

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['name']).to eq(agent_bot.name)
        conversation.reload
        expect(conversation.assignee_agent_bot).to eq(agent_bot)
        expect(conversation.assignee).to be_nil
      end

      it 'assigns a team to the conversation' do
        team_member = create(:user, account: account, role: :agent, auto_offline: false)
        create(:inbox_member, inbox: conversation.inbox, user: team_member)
        create(:team_member, team: team, user: team_member)
        params = { team_id: team.id }

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.team).to eq(team)
        # assignee will be from team
        expect(conversation.reload.assignee).to eq(team_member)
      end
    end

    context 'when it is an authenticated bot with access to the inbox' do
      let(:agent_bot) { create(:agent_bot, account: account) }
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:team) { create(:team, account: account) }

      before do
        create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)
      end

      it 'assignment of an agent in the conversation by bot agent' do
        create(:inbox_member, user: agent, inbox: conversation.inbox)

        conversation.update!(assignee_id: nil)
        expect(conversation.reload.assignee).to be_nil

        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
             headers: { api_access_token: agent_bot.access_token.token },
             params: {
               assignee_id: agent.id
             },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.assignee).to eq(agent)
      end

      it 'assignment of an team in the conversation by bot agent' do
        create(:inbox_member, user: agent, inbox: conversation.inbox)

        conversation.update!(team_id: nil)
        expect(conversation.reload.team).to be_nil

        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
             headers: { api_access_token: agent_bot.access_token.token },
             params: {
               team_id: team.id
             },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.team).to eq(team)
      end
    end

    context 'when assigning a captain mirror bot (admin-only, D-3)' do
      let(:administrator) { create(:user, account: account, role: :administrator) }
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:captain_assistant) { create(:captain_assistant, account: account) }
      let(:captain_mirror) { captain_assistant.mirror_agent_bot }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        # C8: a atribuição de espelho captain exige assistant elegível à inbox
        create(:captain_inbox, captain_assistant: captain_assistant, inbox: conversation.inbox)
      end

      it 'allows an administrator to assign the captain mirror' do
        params = { assignee_id: captain_mirror.id, assignee_type: 'AgentBot' }

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['name']).to eq(captain_mirror.name)
        conversation.reload
        expect(conversation.assignee_agent_bot).to eq(captain_mirror)
        expect(conversation.assignee).to be_nil
      end

      it 'returns forbidden with the i18n error when an agent assigns the captain mirror' do
        params = { assignee_id: captain_mirror.id, assignee_type: 'AgentBot' }

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)
        # `I18n.t` sem `locale:` resolve no idioma do PROCESSO (:en no rails_helper); a resposta
        # sai no idioma da CONTA. Os exemplos logo abaixo, que comparam en x pt_BR, ja passavam
        # justamente porque dizem o locale. Ver 4cab065b87.
        expect(response.parsed_body['error']).to eq(
          I18n.t('conversations.captain.assignment_forbidden', locale: account.locale)
        )
        expect(conversation.reload.assignee_agent_bot).to be_nil
      end

      it 'returns forbidden (not 500) when an agent bot token assigns the captain mirror' do
        webhook_bot = create(:agent_bot, account: account)
        create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: webhook_bot)

        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
             headers: { api_access_token: webhook_bot.access_token.token },
             params: { assignee_id: captain_mirror.id, assignee_type: 'AgentBot' },
             as: :json

        expect(response).to have_http_status(:forbidden)
        expect(conversation.reload.assignee_agent_bot).to be_nil
      end

      it 'allows an administrator to unassign a conversation owned by the captain mirror' do
        conversation.update!(assignee_agent_bot: captain_mirror)

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { assignee_id: nil },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.assignee_agent_bot).to be_nil
      end

      it 'assigns the captain mirror through the service without Current.user (automation/macro/tool path)' do
        result = Conversations::AssignmentService.new(
          conversation: conversation,
          assignee_id: captain_mirror.id,
          assignee_type: 'AgentBot'
        ).perform

        expect(result).to eq(captain_mirror)
        expect(conversation.reload.assignee_agent_bot).to eq(captain_mirror)
      end

      it 'keeps i18n parity between en and pt_BR for the forbidden message' do
        en_message = I18n.t('conversations.captain.assignment_forbidden', locale: :en)
        pt_message = I18n.t('conversations.captain.assignment_forbidden', locale: :pt_BR)

        expect(en_message).to be_present
        expect(pt_message).to be_present
        expect(pt_message).not_to eq(en_message)
      end
    end

    # C8: elegibilidade endurecida — espelho captain só entra em inbox onde o assistant
    # está registrado. 422 explícito p/ UI; no-op silencioso no caminho in-process.
    context 'when assigning a captain mirror bot not eligible for the inbox (C8)' do
      let(:administrator) { create(:user, account: account, role: :administrator) }
      let(:captain_assistant) { create(:captain_assistant, account: account) }
      let(:captain_mirror) { captain_assistant.mirror_agent_bot }

      it 'returns 422 with the i18n error for an admin' do
        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { assignee_id: captain_mirror.id, assignee_type: 'AgentBot' },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(
          I18n.t('conversations.captain.assignment_not_eligible', locale: account.locale)
        )
        expect(conversation.reload.assignee_agent_bot).to be_nil
      end

      it 'no-ops silently through the service (in-process: automação/macro/tool)' do
        result = Conversations::AssignmentService.new(
          conversation: conversation,
          assignee_id: captain_mirror.id,
          assignee_type: 'AgentBot'
        ).perform

        expect(result).to be_nil
        expect(conversation.reload.assignee_agent_bot).to be_nil
      end

      it 'still assigns a webhook agent bot without captain eligibility (comportamento atual preservado)' do
        webhook_bot = create(:agent_bot, account: account)

        result = Conversations::AssignmentService.new(
          conversation: conversation,
          assignee_id: webhook_bot.id,
          assignee_type: 'AgentBot'
        ).perform

        expect(result).to eq(webhook_bot)
        expect(conversation.reload.assignee_agent_bot).to eq(webhook_bot)
      end

      it 'keeps i18n parity between en and pt_BR for the not eligible message' do
        en_message = I18n.t('conversations.captain.assignment_not_eligible', locale: :en)
        pt_message = I18n.t('conversations.captain.assignment_not_eligible', locale: :pt_BR)

        expect(en_message).to be_present
        expect(pt_message).to be_present
        expect(pt_message).not_to eq(en_message)
      end
    end

    context 'when conversation already has an assignee' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        conversation.update!(assignee: agent)
      end

      it 'unassigns the assignee from the conversation' do
        params = { assignee_id: nil }
        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.assignee).to be_nil
        expect(Conversations::ActivityMessageJob)
          .to(have_been_enqueued.at_least(:once)
        .with(conversation.id, { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
                                 content: I18n.t('conversations.activity.assignee.removed', user_name: agent.name,
                                                                                            locale: account.locale) }))
      end
    end

    context 'when conversation already has a team' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:team) { create(:team, account: account) }

      before do
        conversation.update!(team: team)
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        # Regra do fork (isolamento por time): quem não é do time não alcança a
        # conversa — o `authorize_team_access` agora vale também nos sub-recursos.
        # Sem isto o agente de fora removeria o time e, com `team_id` nulo, a
        # conversa cairia no colo dele: escalada de privilégio, não permissão.
        create(:team_member, user: agent, team: team)
      end

      it 'unassigns the team from the conversation' do
        params = { team_id: 0 }
        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.team).to be_nil
      end
    end
  end
end
