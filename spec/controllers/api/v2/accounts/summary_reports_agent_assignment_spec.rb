require 'rails_helper'

RSpec.describe 'Summary Reports API — agent assignment', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:default_timezone) { ActiveSupport::TimeZone[0]&.name }
  let(:start_of_today) { Time.current.in_time_zone(default_timezone).beginning_of_day.to_i }
  let(:end_of_today) { Time.current.in_time_zone(default_timezone).end_of_day.to_i }

  describe 'GET /api/v2/accounts/:account_id/summary_reports/agent_assignment' do
    let(:params) { { since: start_of_today.to_s, until: end_of_today.to_s, business_hours: false } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/agent_assignment"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is a plain agent' do
      it 'is not authorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/agent_assignment",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an admin' do
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before do
        create(:conversation_assignment_history, account: account, conversation: conversation,
                                                 assignee: agent, assigned_by: admin, source: :manual)
      end

      def fetch_report(extra = {})
        get "/api/v2/accounts/#{account.id}/summary_reports/agent_assignment",
            params: params.merge(extra),
            headers: admin.create_new_auth_token,
            as: :json
        response.parsed_body
      end

      it 'returns rows (per agent) and the author→destination matrix' do
        json = fetch_report
        expect(response).to have_http_status(:success)

        agent_row = json['rows'].find { |r| r['id'] == agent.id }
        admin_row = json['rows'].find { |r| r['id'] == admin.id }
        expect(agent_row['received_total']).to eq(1)
        expect(agent_row['received_manual']).to eq(1)
        expect(admin_row['assigned_to_others']).to eq(1)

        pair = json['matrix'].find { |m| m['from_id'] == admin.id && m['to_id'] == agent.id }
        expect(pair['count']).to eq(1)
        expect(pair['from_name']).to eq(admin.name)
        expect(pair['to_name']).to eq(agent.name)
      end

      it 'filters by team' do
        team = create(:team, account: account)
        other_conversation = create(:conversation, account: account, inbox: inbox)
        create(:conversation_assignment_history, account: account, conversation: other_conversation,
                                                 assignee: agent, assigned_by: admin, source: :manual, team: team)

        json = fetch_report(team_id: team.id)
        agent_row = json['rows'].find { |r| r['id'] == agent.id }
        # só a atribuição do time filtrado conta (a do `before` não tem time)
        expect(agent_row['received_total']).to eq(1)
        expect(json['matrix'].sum { |m| m['count'] }).to eq(1)
      end

      it 'filters by inbox' do
        other_inbox = create(:inbox, account: account)
        other_conversation = create(:conversation, account: account, inbox: other_inbox)
        create(:conversation_assignment_history, account: account, conversation: other_conversation,
                                                 assignee: agent, assigned_by: admin, source: :manual)

        # sem filtro seriam 2; filtrando pela inbox original conta só 1
        json = fetch_report(inbox_id: inbox.id)
        agent_row = json['rows'].find { |r| r['id'] == agent.id }
        expect(agent_row['received_total']).to eq(1)
      end
    end
  end
end
