require 'rails_helper'

RSpec.describe 'CSAT Survey Responses API', type: :request do
  let(:account) { create(:account) }
  let!(:csat_survey_response) { create(:csat_survey_response, account: account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/csat_survey_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns all the csat survey responses for administrators' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.first['feedback_message']).to eq(csat_survey_response.feedback_message)
      end

      it 'filters csat responses based on a date range' do
        csat_10_days_ago = create(:csat_survey_response, account: account, created_at: 10.days.ago)
        csat_3_days_ago = create(:csat_survey_response, account: account, created_at: 3.days.ago)

        get "/api/v1/accounts/#{account.id}/csat_survey_responses",
            params: { since: 5.days.ago.to_time.to_i.to_s, until: Time.zone.today.to_time.to_i.to_s },
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data.pluck('id')).to include(csat_3_days_ago.id)
        expect(response_data.pluck('id')).not_to include(csat_10_days_ago.id)
      end

      it 'filters csat responses based on a date range and agent ids' do
        csat1_assigned_agent = create(:user, account: account, role: :agent)
        csat2_assigned_agent = create(:user, account: account, role: :agent)

        create(:csat_survey_response, account: account, created_at: 10.days.ago, assigned_agent: csat1_assigned_agent)
        create(:csat_survey_response, account: account, created_at: 3.days.ago, assigned_agent: csat2_assigned_agent)
        create(:csat_survey_response, account: account, created_at: 5.days.ago)

        get "/api/v1/accounts/#{account.id}/csat_survey_responses",
            params: { since: 11.days.ago.to_time.to_i.to_s, until: Time.zone.today.to_time.to_i.to_s,
                      user_ids: [csat1_assigned_agent.id, csat2_assigned_agent.id] },
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data.size).to eq 2
      end

      it 'returns csat responses even if the agent is deleted from account' do
        deleted_agent_csat = create(:csat_survey_response, account: account, assigned_agent: agent)
        deleted_agent_csat.assigned_agent.account_users.destroy_all

        get "/api/v1/accounts/#{account.id}/csat_survey_responses",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/csat_survey_responses/metrics' do
    context 'with surveys in different inboxes, teams and agents' do
      let(:inbox_a) { create(:inbox, account: account) }
      let(:inbox_b) { create(:inbox, account: account) }
      let(:team_a) { create(:team, account: account) }
      let(:team_b) { create(:team, account: account) }
      let(:agent_b) { create(:user, account: account, role: :agent) }
      let(:conversation_a) { create(:conversation, account: account, inbox: inbox_a, team: team_a, assignee: agent) }
      let(:conversation_b) { create(:conversation, account: account, inbox: inbox_b, team: team_b, assignee: agent_b) }

      before do
        csat_survey_response.destroy!
        create(:team_member, team: team_a, user: agent)
        create(:team_member, team: team_b, user: agent_b)
        3.times { create(:message, account: account, conversation: conversation_a, content_type: :input_csat) }
        create(:message, account: account, conversation: conversation_b, content_type: :input_csat)
        create(:csat_survey_response, account: account, conversation: conversation_a, assigned_agent: agent, rating: 5)
        create(:csat_survey_response, account: account, conversation: conversation_a, assigned_agent: agent, rating: 1)
        create(:csat_survey_response, account: account, conversation: conversation_b, assigned_agent: agent_b, rating: 1)
      end

      def metrics_for(filters = {})
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/metrics",
            params: filters, headers: administrator.create_new_auth_token, as: :json
        response.parsed_body
      end

      it 'counts only surveys sent from the selected inbox' do
        metrics = metrics_for(inbox_id: inbox_a.id)
        expect(metrics).to include('total_count' => 2, 'total_response_count_for_rate' => 2, 'total_sent_messages_count' => 3)
      end

      it 'counts only surveys sent from the selected team' do
        metrics = metrics_for(team_id: team_a.id)
        expect(metrics).to include('total_count' => 2, 'total_response_count_for_rate' => 2, 'total_sent_messages_count' => 3)
      end

      it 'counts only surveys sent for the selected agent' do
        expect(conversation_a.reload.assignee_id).to eq(agent.id)
        metrics = metrics_for(user_ids: [agent.id])
        expect(metrics).to include('total_count' => 2, 'total_response_count_for_rate' => 2, 'total_sent_messages_count' => 3)
      end

      it 'ignores the rating only for the response rate counts' do
        without_rating = metrics_for(inbox_id: inbox_a.id)
        with_rating = metrics_for(inbox_id: inbox_a.id, rating: 5)
        expect(with_rating).to include('total_count' => 1, 'ratings_count' => { '5' => 1 })
        expect(with_rating).to include('total_response_count_for_rate' => 2, 'total_sent_messages_count' => 3)
        expect(with_rating.values_at('total_response_count_for_rate', 'total_sent_messages_count')).to eq(
          without_rating.values_at('total_response_count_for_rate', 'total_sent_messages_count')
        )
      end

      it 'preserves the unfiltered totals' do
        metrics = metrics_for
        expect(metrics).to include('total_count' => 3, 'total_response_count_for_rate' => 3, 'total_sent_messages_count' => 4)
        expect(metrics['ratings_count']).to eq({ '1' => 2, '5' => 1 })
      end
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/metrics"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/metrics",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns csat metrics for administrators' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/metrics",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['total_count']).to eq 1
        expect(response_data['total_sent_messages_count']).to eq 0
        expect(response_data['ratings_count']).to eq({ '1' => 1 })
      end

      it 'includes an additive csat signal for the semáforo' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/metrics",
            headers: administrator.create_new_auth_token,
            as: :json

        signals = response.parsed_body['signals']
        expect(signals).to be_an(Array)
        csat = signals.find { |s| s['metric'] == 'csat' }
        # única resposta é rating 1 => satisfação 0% => bad, e é highlight e attention
        expect(csat).to include('metric' => 'csat', 'value' => 0, 'goal' => 85, 'level' => 'bad',
                                'is_highlight' => true, 'is_attention' => true)
      end

      it 'does not judge satisfaction when nobody answered the survey' do
        CsatSurveyResponse.destroy_all

        get "/api/v1/accounts/#{account.id}/csat_survey_responses/metrics",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response.parsed_body['total_count']).to eq 0
        expect(response.parsed_body['signals']).to eq([])
      end

      it 'filters csat metrics based on a date range' do
        # clearing any existing csat responses
        CsatSurveyResponse.destroy_all

        create(:csat_survey_response, account: account, created_at: 10.days.ago)
        create(:csat_survey_response, account: account, created_at: 3.days.ago)

        get "/api/v1/accounts/#{account.id}/csat_survey_responses/metrics",
            params: { since: 5.days.ago.to_time.to_i.to_s, until: Time.zone.today.to_time.to_i.to_s },
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['total_count']).to eq 1
        expect(response_data['total_sent_messages_count']).to eq 0
        expect(response_data['ratings_count']).to eq({ '1' => 1 })
      end

      it 'filters csat metrics based on a date range and agent ids' do
        csat1_assigned_agent = create(:user, account: account, role: :agent)
        csat2_assigned_agent = create(:user, account: account, role: :agent)

        create(:csat_survey_response, account: account, created_at: 10.days.ago, assigned_agent: csat1_assigned_agent)
        create(:csat_survey_response, account: account, created_at: 3.days.ago, assigned_agent: csat2_assigned_agent)
        create(:csat_survey_response, account: account, created_at: 5.days.ago)

        get "/api/v1/accounts/#{account.id}/csat_survey_responses/metrics",
            params: { since: 11.days.ago.to_time.to_i.to_s, until: Time.zone.today.to_time.to_i.to_s,
                      user_ids: [csat1_assigned_agent.id, csat2_assigned_agent.id] },
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['total_count']).to eq 2
        expect(response_data['total_sent_messages_count']).to eq 0
        expect(response_data['ratings_count']).to eq({ '1' => 2 })
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/csat_survey_responses/download' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/download"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:params) { { since: 5.days.ago.to_time.to_i.to_s, until: Time.zone.tomorrow.to_time.to_i.to_s } }

      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/download",
            params: params,
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns summary' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/download",
            params: params,
            headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)

        content = CSV.parse(response.body)
        # Check rating from CSAT Row
        expect(content[1][1]).to eq '1'
        expect(content.length).to eq 3
      end

      it 'escapes formula-like feedback and contact names' do
        formula = '=HYPERLINK("http://x","y")'
        csat_survey_response.update!(feedback_message: formula, contact: create(:contact, account: account, name: formula))

        get "/api/v1/accounts/#{account.id}/csat_survey_responses/download",
            params: params,
            headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        row = CSV.parse(response.body)[1]
        expect(row[2]).to eq("'#{formula}")
        expect(row[3]).to eq("'#{formula}")
      end
    end
  end
end
