require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::LiveReports', type: :request do
  let(:account) { create(:account) }
  # `pending_status_allowed_by_inbox` (nossa, da2ea07ed1) recusa Pendente em caixa que
  # nao habilitou o recurso. Este spec vem do upstream e presume que Pendente sempre
  # funciona; as conversas pendentes abaixo passam a nascer nesta caixa.
  let!(:caixa_pendente) { create(:inbox, account: account, pending_status_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:team) { create(:team, account: account) }
  let(:team_member) { create(:team_member, team: team, user: admin) }

  describe 'GET /api/v2/accounts/{account.id}/live_reports/conversation_metrics' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/live_reports/conversation_metrics"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated but not authorized' do
      it 'returns forbidden' do
        get "/api/v2/accounts/#{account.id}/live_reports/conversation_metrics",
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated and authorized' do
      before do
        create(:conversation, :with_assignee, account: account, status: :open)
        create(:conversation, account: account, status: :open)
        create(:conversation, :with_assignee, account: account, inbox: caixa_pendente, status: :pending)
        create(:conversation, :with_assignee, account: account, status: :open) do |conversation|
          create(:message, account: account, conversation: conversation, message_type: :outgoing)
        end
      end

      it 'returns conversation metrics' do
        get "/api/v2/accounts/#{account.id}/live_reports/conversation_metrics",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        response_data = response.parsed_body
        expect(response_data['open']).to eq(3)
        expect(response_data['unattended']).to eq(2)
        expect(response_data['unassigned']).to eq(1)
        expect(response_data['pending']).to eq(1)
      end

      context 'with team_id parameter' do
        before do
          create(:conversation, account: account, status: :open, team_id: team.id)
          create(:conversation, account: account, status: :open)
        end

        it 'returns metrics filtered by team' do
          get "/api/v2/accounts/#{account.id}/live_reports/conversation_metrics",
              params: { team_id: team.id },
              headers: admin.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)

          response_data = response.parsed_body
          expect(response_data['open']).to eq(1)
          expect(response_data['unattended']).to eq(1)
          expect(response_data['unassigned']).to eq(1)
          expect(response_data['pending']).to eq(0)
        end
      end
    end
  end

  describe 'GET /api/v2/accounts/{account.id}/live_reports/grouped_conversation_metrics' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/live_reports/grouped_conversation_metrics",
            params: { group_by: 'team_id' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated but not authorized' do
      it 'returns forbidden' do
        get "/api/v2/accounts/#{account.id}/live_reports/grouped_conversation_metrics",
            params: { group_by: 'team_id' },
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid group_by parameter' do
      it 'returns unprocessable_entity error' do
        get "/api/v2/accounts/#{account.id}/live_reports/grouped_conversation_metrics",
            params: { group_by: 'invalid_param' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid group_by')
      end
    end

    context 'when grouped by team_id' do
      let(:assignee1) { create(:user, account: account) }

      before do
        create(:conversation, account: account, status: :open, team_id: team.id)
        create(:conversation, account: account, status: :open, team_id: team.id)
        create(:conversation, account: account, status: :open, team_id: team.id) do |conversation|
          create(:message, account: account, conversation: conversation, message_type: :outgoing)
        end

        create(:conversation, account: account, status: :open, assignee_id: assignee1.id)
        create(:conversation, account: account, status: :open) do |conversation|
          create(:message, account: account, conversation: conversation, message_type: :outgoing)
        end
      end

      it 'returns metrics grouped by team' do
        get "/api/v2/accounts/#{account.id}/live_reports/grouped_conversation_metrics",
            params: { group_by: 'team_id' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        response_data = response.parsed_body
        expect(response_data.size).to eq(2)
        expect(response_data).to include(
          { 'team_id' => nil, 'open' => 2, 'unattended' => 1, 'unassigned' => 1 }
        )
        expect(response_data).to include(
          { 'team_id' => team.id, 'open' => 3, 'unattended' => 2, 'unassigned' => 3 }
        )
      end
    end

    context 'when filtering by assignee_id' do
      let(:assignee1) { create(:user, account: account) }

      before do
        create(:conversation, assignee_id: agent.id, account: account, status: :open)
        create(:conversation, account: account, status: :open)
        create(:conversation, assignee_id: agent.id, account: account, status: :open) do |conversation|
          create(:message, account: account, conversation: conversation, message_type: :outgoing)
        end
      end

      it 'returns metrics grouped by assignee' do
        get "/api/v2/accounts/#{account.id}/live_reports/grouped_conversation_metrics",
            params: { group_by: 'assignee_id' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        response_data = response.parsed_body
        expect(response_data.size).to eq 2
        expect(response_data).to include(
          { 'assignee_id' => agent.id, 'open' => 2, 'unassigned' => 0, 'unattended' => 1 }
        )
        expect(response_data).to include(
          { 'assignee_id' => nil, 'open' => 1, 'unassigned' => 1, 'unattended' => 1 }
        )
      end
    end
  end

  describe 'GET /api/v2/accounts/{account.id}/live_reports/in_service_overview' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_overview"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated but not authorized' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_overview",
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated and authorized' do
      let(:assignee1) { create(:user, account: account) }
      let(:assignee2) { create(:user, account: account) }

      before do
        create(:conversation, account: account, status: :open, assignee_id: assignee1.id)
        create(:conversation, account: account, status: :open)
        create(:conversation, account: account, inbox: caixa_pendente, status: :pending, assignee_id: assignee2.id)
        create(:conversation, account: account, inbox: caixa_pendente, status: :pending)
        create(:conversation, account: account, status: :resolved, assignee_id: assignee1.id, team_id: team.id)
      end

      it 'returns aggregated in-service metrics' do
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_overview",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        response_data = response.parsed_body
        expect(response_data['generated_at']).to be_present
        expect(response_data['totals']).to include(
          'in_service' => 4,
          'waiting' => 3,
          'agents_with_conversations' => 2
        )

        expect(response_data['agents']).to include(
          { 'assignee_id' => assignee1.id, 'in_service' => 1, 'open' => 1, 'pending' => 0 }
        )
        expect(response_data['agents']).to include(
          { 'assignee_id' => assignee2.id, 'in_service' => 1, 'open' => 0, 'pending' => 1 }
        )
      end

      it 'filters by team_id when provided' do
        create(:conversation, account: account, status: :open, team_id: team.id)
        create(:conversation, account: account, inbox: caixa_pendente, status: :pending)

        get "/api/v2/accounts/#{account.id}/live_reports/in_service_overview",
            params: { team_id: team.id },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        response_data = response.parsed_body
        expect(response_data['totals']).to include(
          'in_service' => 1,
          'waiting' => 1
        )
      end
    end

    context 'when authenticated and authorized with no in-service conversations' do
      it 'returns empty metrics' do
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_overview",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        response_data = response.parsed_body
        expect(response_data['totals']).to include(
          'in_service' => 0,
          'waiting' => 0,
          'agents_with_conversations' => 0
        )
        expect(response_data['agents']).to eq([])
      end
    end
  end

  describe 'GET /api/v2/accounts/{account.id}/live_reports/in_service_conversations' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'agent', assignee_id: admin.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated but not authorized' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'agent', assignee_id: admin.id },
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated and authorized' do
      let(:assignee1) { create(:user, account: account) }

      it 'returns unprocessable_entity for invalid scope' do
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'invalid' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid scope')
      end

      it 'returns unprocessable_entity for scope=agent without assignee_id' do
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'agent' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('assignee_id is required for scope=agent')
      end

      it 'returns paginated conversations for an agent with keyset cursor' do
        6.times do |i|
          create(:conversation,
                 account: account,
                 status: :open,
                 assignee_id: assignee1.id,
                 last_activity_at: (6 - i).minutes.ago)
        end

        get(
          "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
          params: { scope: 'agent', assignee_id: assignee1.id, limit: 5 },
          headers: admin.create_new_auth_token,
          as: :json
        )

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['scope']).to eq('agent')
        expect(response_data['assignee_id']).to eq(assignee1.id)
        expect(response_data['payload'].length).to eq(5)
        expect(response_data.dig('meta', 'has_more')).to eq(true)
        expect(response_data.dig('meta', 'next_cursor')).to be_present

        get(
          "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
          params: {
            scope: 'agent',
            assignee_id: assignee1.id,
            limit: 5,
            cursor: response_data.dig('meta', 'next_cursor')
          },
          headers: admin.create_new_auth_token,
          as: :json
        )

        expect(response).to have_http_status(:success)
        second_data = response.parsed_body
        expect(second_data['payload'].length).to eq(1)
        expect(second_data.dig('meta', 'has_more')).to eq(false)
      end

      it 'returns waiting conversations for scope=waiting' do
        open_assigned = create(:conversation, account: account, status: :open, assignee_id: assignee1.id)
        open_unassigned = create(:conversation, account: account, status: :open)
        pending_assigned = create(:conversation, account: account, inbox: caixa_pendente, status: :pending, assignee_id: assignee1.id)
        pending_unassigned = create(:conversation, account: account, inbox: caixa_pendente, status: :pending)

        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'waiting', limit: 20 },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to include(open_unassigned.display_id, pending_assigned.display_id, pending_unassigned.display_id)
        expect(ids).not_to include(open_assigned.display_id)
      end

      it 'clamps limit to maximum of 20' do
        30.times do |i|
          create(:conversation,
                 account: account,
                 status: :open,
                 assignee_id: assignee1.id,
                 last_activity_at: (30 - i).minutes.ago)
        end

        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'agent', assignee_id: assignee1.id, limit: 100 },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].length).to eq(20)
      end

      it 'uses default limit of 5 when limit is not provided' do
        6.times do |i|
          create(:conversation,
                 account: account,
                 status: :open,
                 assignee_id: assignee1.id,
                 last_activity_at: (6 - i).minutes.ago)
        end

        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'agent', assignee_id: assignee1.id },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].length).to eq(5)
      end

      # O arranjo anterior criava a conversa "excluida" SEM time e contava que ela ficasse assim.
      # Nao fica: `AssignmentHandler#sync_team_from_assignee` poe o time do responsavel quando ele
      # pertence a EXATAMENTE UM — e assignee1 acabara de virar membro de `team`. As duas conversas
      # terminavam no mesmo time e o filtro nunca era exercitado.
      #
      # Com o agente em DOIS times, o sync nao sobrescreve um team_id que ja e de um deles, entao
      # as duas conversas ficam com o MESMO responsavel e times DIFERENTES — que e exatamente o que
      # isola o filtro por time do filtro por responsavel.
      it 'applies team filter when provided' do
        outro_time = create(:team, account: account)
        create(:team_member, team: team, user: assignee1)
        create(:team_member, team: outro_time, user: assignee1)
        included = create(:conversation, account: account, status: :open, assignee_id: assignee1.id, team_id: team.id)
        excluded = create(:conversation, account: account, status: :open, assignee_id: assignee1.id,
                                         team_id: outro_time.id)

        # SEM `as: :json`: num GET esse modificador manda os params no CORPO e a query string
        # fica vazia — o `team_id` nunca chegava ao controller, entao o filtro por time nao era
        # exercitado e a conversa sem time aparecia no resultado. Mesmo caso do contacts/search.
        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'agent', assignee_id: assignee1.id, team_id: team.id },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to include(included.display_id)
        expect(ids).not_to include(excluded.display_id)
      end

      it 'returns success with fallback payload when contact avatar serialization fails' do
        contact = create(:contact, account: account, name: 'Maria da Silva')
        conversation = create(
          :conversation,
          account: account,
          status: :open,
          assignee_id: assignee1.id,
          contact: contact
        )
        create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Hi there')

        allow_any_instance_of(Contact).to receive(:avatar_url).and_raise(StandardError, 'invalid avatar')

        get "/api/v2/accounts/#{account.id}/live_reports/in_service_conversations",
            params: { scope: 'agent', assignee_id: assignee1.id },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        payload = response.parsed_body['payload'].first
        expect(payload).to include(
          'id' => conversation.display_id,
          'status' => conversation.status,
          'contact_name' => 'Maria da Silva',
          'contact_avatar' => ''
        )
        expect(payload['last_message']).to be_present
      end
    end
  end
end
