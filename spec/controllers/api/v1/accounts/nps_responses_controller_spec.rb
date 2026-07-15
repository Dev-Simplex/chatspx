require 'rails_helper'

RSpec.describe 'NPS Responses API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  def get_metrics(params = {})
    get "/api/v1/accounts/#{account.id}/nps_responses/metrics",
        params: params, headers: administrator.create_new_auth_token, as: :json
    response.parsed_body
  end

  describe 'GET /api/v1/accounts/{account.id}/nps_responses/metrics' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/nps_responses/metrics"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a reliable sample (N >= 30)' do
      before do
        # 24 promotores (10) + 6 detratores (3) => NPS (24-6)/30*100 = 60
        create_list(:nps_response, 24, :promoter, account: account, status: :responded)
        create_list(:nps_response, 6, :detractor, account: account, status: :responded)
      end

      it 'returns an integer NPS score computed from a single source' do
        body = get_metrics
        expect(response).to have_http_status(:success)
        expect(body['nps_score']).to eq(60)
        expect(body['total_count']).to eq(30)
        expect(body['reliable']).to be(true)
        expect(body['min_sample']).to eq(Reports::NpsCalculator::MIN_SAMPLE)
      end

      it 'emits an nps signal whose value matches the score' do
        nps = get_metrics['signals'].find { |s| s['metric'] == 'nps' }
        expect(nps).to include('metric' => 'nps', 'value' => 60, 'goal' => 50, 'level' => 'good',
                               'is_highlight' => true, 'is_attention' => false)
      end

      it 'derives the nps level from PdfBenchmarks (same source as the PDF)' do
        nps = get_metrics['signals'].find { |s| s['metric'] == 'nps' }
        bench = Reports::PdfBenchmarks::BENCHMARKS[:nps]
        expect(nps['level']).to eq(Reports::PdfBenchmarks.level_for(nps['value'].to_f, bench).to_s)
      end
    end

    context 'when computing response rate over a consistent cohort' do
      before do
        # 30 respondidas (trusted) + 10 enviadas + 10 expiradas => 50 no denominador
        create_list(:nps_response, 30, :promoter, account: account, status: :responded)
        create_list(:nps_response, 10, :promoter, account: account, status: :sent)
        create_list(:nps_response, 10, :promoter, account: account, status: :expired)
      end

      it 'computes response_rate as responded / sent from the same cohort' do
        body = get_metrics
        # 30 / 50 * 100 = 60.0 — nunca ultrapassa 100 e respeita os filtros
        expect(body['response_rate']).to eq(60.0)
        expect(body['total_sent_count']).to eq(50)
      end
    end

    context 'with a low sample (N < 30)' do
      before do
        create_list(:nps_response, 8, :promoter, account: account, status: :responded)
        create_list(:nps_response, 2, :detractor, account: account, status: :responded)
      end

      it 'flags the result as unreliable' do
        body = get_metrics
        expect(body['nps_score']).to eq(60)
        expect(body['reliable']).to be(false)
      end
    end

    context 'when comparing with the previous period' do
      # Query string do axios chega como String (o range usa DateTime.strptime).
      let(:since_ts) { 7.days.ago.to_i.to_s }
      let(:until_ts) { Time.current.to_i.to_s }

      before do
        # Período atual (criadas há 3 dias): 24 promotores + 6 detratores => NPS 60
        create_list(:nps_response, 24, :promoter, account: account, status: :responded, created_at: 3.days.ago)
        create_list(:nps_response, 6, :detractor, account: account, status: :responded, created_at: 3.days.ago)
        # Período anterior (criadas há 10 dias): 15 promotores + 15 detratores => NPS 0
        create_list(:nps_response, 15, :promoter, account: account, status: :responded, created_at: 10.days.ago)
        create_list(:nps_response, 15, :detractor, account: account, status: :responded, created_at: 10.days.ago)
      end

      it 'returns the previous score and the point delta' do
        body = get_metrics(since: since_ts, until: until_ts)
        expect(body['nps_score']).to eq(60)
        expect(body['previous_nps_score']).to eq(0)
        expect(body['nps_delta']).to eq(60)
      end
    end
  end
end
