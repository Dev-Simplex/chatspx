require 'rails_helper'

RSpec.describe 'Report PDF Exports API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'POST /api/v1/accounts/{account.id}/report_pdf_exports' do
    let(:params) { { report_type: 'nps', since: '1735689600', until: '1749340800' } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/report_pdf_exports", params: params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized (reports are admin-only)' do
        post "/api/v1/accounts/#{account.id}/report_pdf_exports",
             headers: agent.create_new_auth_token, params: params, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'creates a pending export and enqueues the job' do
        expect do
          post "/api/v1/accounts/#{account.id}/report_pdf_exports",
               headers: administrator.create_new_auth_token, params: params, as: :json
        end.to have_enqueued_job(Reports::PdfExportJob)

        expect(response).to have_http_status(:accepted)
        body = response.parsed_body
        expect(body['report_type']).to eq('nps')
        expect(body['status']).to eq('pending')
        expect(ReportPdfExport.last.filters).to include('since' => '1735689600', 'until' => '1749340800')
      end

      it 'rejects an unsupported report_type' do
        post "/api/v1/accounts/#{account.id}/report_pdf_exports",
             headers: administrator.create_new_auth_token,
             params: { report_type: 'unknown' }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/report_pdf_exports/{id}' do
    let(:export) { create(:report_pdf_export, account: account, status: :completed) }

    it 'returns the export status' do
      get "/api/v1/accounts/#{account.id}/report_pdf_exports/#{export.id}",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('completed')
    end

    it 'does not leak exports from other accounts' do
      other_export = create(:report_pdf_export, account: create(:account))

      get "/api/v1/accounts/#{account.id}/report_pdf_exports/#{other_export.id}",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
