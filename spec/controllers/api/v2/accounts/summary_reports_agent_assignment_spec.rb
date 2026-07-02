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

      it 'returns the assignment report per agent' do
        get "/api/v2/accounts/#{account.id}/summary_reports/agent_assignment",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        agent_row = json_response.find { |r| r['id'] == agent.id }
        admin_row = json_response.find { |r| r['id'] == admin.id }

        expect(agent_row['received_total']).to eq(1)
        expect(agent_row['received_manual']).to eq(1)
        expect(admin_row['assigned_to_others']).to eq(1)
      end
    end
  end
end
