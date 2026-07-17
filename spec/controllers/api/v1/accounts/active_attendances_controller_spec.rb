require 'rails_helper'

RSpec.describe 'Active Attendances API', type: :request do
  let(:account) { create(:account) }
  # pending_status_enabled: a Conversation valida status pending contra a inbox
  # (conversation.rb:347) — sem isso o factory levanta RecordInvalid.
  let(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }

  describe 'GET /api/v1/accounts/{account.id}/active_attendances' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/active_attendances"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    # A abertura desta aba é DENTRO da conta (D2) — a fronteira entre contas
    # continua fechada, e é a única que o gate de privacidade aqui precisa manter.
    context 'when the user belongs to another account' do
      it 'does not leak attendances across accounts' do
        other_account = create(:account)
        outsider = create(:user, account: other_account, role: :administrator)
        create(:conversation, account: account, inbox: inbox, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: outsider.create_new_auth_token, as: :json

        expect(response).not_to have_http_status(:success)
        expect(response.body).not_to include('payload')
      end
    end

    context 'when it is an authenticated agent' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:owner) { create(:user, account: account, role: :agent) }

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'returns conversations in service and omits resolved ones' do
        open_conversation = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)
        pending_conversation = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :pending)
        snoozed_conversation = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :snoozed)
        create(:conversation, account: account, inbox: inbox, assignee: owner, status: :resolved)

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['meta']['count']).to eq(3)
        expect(body['payload'].pluck('id')).to contain_exactly(
          open_conversation.display_id, pending_conversation.display_id, snoozed_conversation.display_id
        )
      end

      # D2 — "atendimento geral": o agente PRECISA enxergar que outro time já
      # atende o contato; é essa cegueira que causa o atendimento duplicado.
      # Esta spec trava contra alguém "consertar" o controller com o
      # Conversations::PermissionFilterService, que devolveria lista incompleta.
      it 'shows attendances owned by a team the requesting agent does not belong to' do
        other_team = create(:team, account: account)
        other_inbox = create(:inbox, account: account)
        conversation = create(:conversation, account: account, inbox: other_inbox, team: other_team, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['payload'].pluck('id')).to include(conversation.display_id)
        expect(body['payload'].first['team']).to include('id' => other_team.id, 'name' => other_team.name)
      end

      # O requisito do dono: a aba não mostra NENHUM trecho de conversa. Blinda
      # contra reuso acidental do _conversation.json.jbuilder, que emite
      # json.messages [last_message.push_event_data].
      it 'never exposes message content' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)
        create(:message, account: account, inbox: inbox, conversation: conversation, content: 'segredo do cliente')

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

        payload = response.parsed_body['payload'].first
        expect(payload).not_to have_key('messages')
        expect(payload).not_to have_key('unread_count')
        expect(response.body).not_to include('segredo do cliente')
      end

      it 'exposes contact, inbox, status and timestamps as metadata only' do
        contact = create(:contact, account: account, name: 'Fulano', phone_number: '+5511999999999', email: 'fulano@example.com')
        create(:conversation, account: account, inbox: inbox, contact: contact, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

        payload = response.parsed_body['payload'].first
        expect(payload['contact']).to include('id' => contact.id, 'name' => 'Fulano', 'phone_number' => '+5511999999999')
        expect(payload['inbox']).to include('id' => inbox.id, 'name' => inbox.name, 'channel_type' => inbox.channel_type)
        expect(payload['status']).to eq('open')
        expect(payload['created_at']).to be_present
      end

      context 'with assignee variants' do
        it 'serializes a human assignee' do
          create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

          expect(response.parsed_body['payload'].first['assignee']).to include(
            'id' => owner.id, 'name' => owner.name, 'type' => 'user'
          )
        end

        it 'serializes a captain mirror assignee as agent_bot' do
          assistant = create(:captain_assistant, account: account)
          mirror = assistant.mirror_agent_bot
          conversation = create(:conversation, account: account, inbox: inbox, status: :open)
          conversation.update!(assignee_agent_bot: mirror)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

          expect(response.parsed_body['payload'].first['assignee']).to include(
            'id' => mirror.id, 'name' => mirror.name, 'type' => 'agent_bot', 'is_captain' => true
          )
        end

        it 'omits the assignee when the conversation has no owner' do
          create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

          expect(response.parsed_body['payload'].first).not_to have_key('assignee')
        end

        it 'omits the team when the conversation has none' do
          create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

          expect(response.parsed_body['payload'].first).not_to have_key('team')
        end
      end

      # A Fase 2 usa este filtro como FONTE DE VERDADE do aviso — nunca o
      # contactConversations, que devolve vazio p/ agente de outro time.
      it 'filters by contact_id' do
        contact = create(:contact, account: account)
        mine = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: owner, status: :open)
        create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances",
            params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json

        body = response.parsed_body
        expect(body['meta']['count']).to eq(1)
        expect(body['payload'].first['id']).to eq(mine.display_id)
      end

      it 'paginates with a stable order' do
        create_list(:conversation, 17, account: account, inbox: inbox, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances",
            params: { page: 2 }, headers: agent.create_new_auth_token, as: :json

        body = response.parsed_body
        expect(body['meta']['count']).to eq(17)
        expect(body['meta']['current_page']).to eq(2)
        expect(body['payload'].length).to eq(2)
      end

      it 'does not issue more queries as more attendances are listed' do
        create(:conversation, account: account, inbox: inbox, team: create(:team, account: account),
                              assignee: create(:user, account: account, role: :agent), status: :open)
        baseline = count_queries do
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
        end

        4.times do
          create(:conversation, account: account, inbox: create(:inbox, account: account),
                                team: create(:team, account: account),
                                assignee: create(:user, account: account, role: :agent), status: :open)
        end
        scaled = count_queries do
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
        end

        expect(response.parsed_body['payload'].length).to eq(5)
        expect(scaled).to eq(baseline)
      end
    end
  end

  def count_queries(&)
    count = 0
    counter = lambda { |_name, _started, _finished, _id, payload|
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] || payload[:sql].match?(/^\s*(BEGIN|COMMIT|RELEASE|SAVEPOINT|ROLLBACK)/i)
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end
end
