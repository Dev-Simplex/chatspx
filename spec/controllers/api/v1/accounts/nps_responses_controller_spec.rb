require 'rails_helper'

RSpec.describe 'NPS Responses API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/nps_responses/metrics' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/nps_responses/metrics"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      before do
        # 8 promotores (score 10) + 2 detratores (score 3) => NPS 60 (good)
        8.times { create(:nps_response, :promoter, account: account, status: :responded) }
        2.times { create(:nps_response, :detractor, account: account, status: :responded) }
      end

      it 'includes an additive nps signal for the semáforo' do
        get "/api/v1/accounts/#{account.id}/nps_responses/metrics",
            headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        # Não remove campos pré-existentes
        expect(body).to include('nps_score', 'total_count', 'promoters_count', 'detractors_count', 'response_rate')

        signals = body['signals']
        expect(signals).to be_an(Array)
        nps = signals.find { |s| s['metric'] == 'nps' }
        expect(nps).to include('metric' => 'nps', 'value' => 60.0, 'goal' => 50, 'level' => 'good',
                               'is_highlight' => true, 'is_attention' => false)
      end

      it 'derives the nps level from PdfBenchmarks (same source as the PDF)' do
        get "/api/v1/accounts/#{account.id}/nps_responses/metrics",
            headers: administrator.create_new_auth_token, as: :json

        nps = response.parsed_body['signals'].find { |s| s['metric'] == 'nps' }
        bench = Reports::PdfBenchmarks::BENCHMARKS[:nps]
        expect(nps['level']).to eq(Reports::PdfBenchmarks.level_for(nps['value'].to_f, bench).to_s)
      end
    end
  end
end
