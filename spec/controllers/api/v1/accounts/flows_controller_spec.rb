require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::FlowsController', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/{account.id}/flows' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/flows"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the account flows' do
        create(:flow, account: account, name: 'Flow A')
        get "/api/v1/accounts/#{account.id}/flows", headers: administrator.create_new_auth_token
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].pluck('name')).to include('Flow A')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/flows' do
    let(:node) { { id: 'n1', type: 'action', action_name: 'add_label', action_params: ['vip'] } }
    let(:valid_params) { { name: 'Novo Flow', trigger_type: 'manual', definition: { nodes: [node], edges: [] } } }

    it 'returns unauthorized when unauthenticated' do
      post "/api/v1/accounts/#{account.id}/flows"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates a flow with its definition' do
      expect do
        post "/api/v1/accounts/#{account.id}/flows", params: valid_params, headers: administrator.create_new_auth_token, as: :json
      end.to change(Flow, :count).by(1)
      expect(response).to have_http_status(:success)
      flow = Flow.last
      expect(flow.name).to eq('Novo Flow')
      expect(flow.nodes.first['action_name']).to eq('add_label')
      expect(flow.created_by).to eq(administrator)
    end

    it 'rejects an invalid definition (unsupported action)' do
      bad = valid_params.merge(definition: { nodes: [{ id: 'n1', type: 'action', action_name: 'do_evil' }], edges: [] })
      post "/api/v1/accounts/#{account.id}/flows", params: bad, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/flows/{id}' do
    it 'updates a flow' do
      flow = create(:flow, account: account, created_by: administrator, visibility: :global)
      patch "/api/v1/accounts/#{account.id}/flows/#{flow.id}", params: { name: 'Renamed' }, headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(flow.reload.name).to eq('Renamed')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/flows/{id}' do
    it 'destroys a flow' do
      flow = create(:flow, account: account, created_by: administrator, visibility: :global)
      expect do
        delete "/api/v1/accounts/#{account.id}/flows/#{flow.id}", headers: administrator.create_new_auth_token
      end.to change(Flow, :count).by(-1)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/flows/{id}/execute' do
    it 'enqueues the execution job' do
      flow = create(:flow, account: account, created_by: administrator, visibility: :global)
      conversation = create(:conversation, account: account)
      expect(Flows::ExecutionJob).to receive(:perform_later)
        .with(flow.id, conversation_ids: [conversation.display_id.to_s], user_id: administrator.id)
      post "/api/v1/accounts/#{account.id}/flows/#{flow.id}/execute",
           params: { conversation_ids: [conversation.display_id] }, headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/flows/import' do
    before do
      create(:macro, account: account, name: 'Boas-vindas',
                     actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] }])
      create(:automation_rule, account: account, name: 'Regra', event_name: 'conversation_created',
                               actions: [{ 'action_name' => 'add_label', 'action_params' => ['novo'] }])
    end

    it 'returns unauthorized when unauthenticated' do
      post "/api/v1/accounts/#{account.id}/flows/import"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'imports macros and automation rules as flows and returns them' do
      expect do
        post "/api/v1/accounts/#{account.id}/flows/import", headers: administrator.create_new_auth_token
      end.to change(Flow, :count).by(2)
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['dry_run']).to be(false)
      expect(body['summary']['macros']).to eq(1)
      expect(body['summary']['automation_rules']).to eq(1)
      expect(body['flows'].pluck('name')).to contain_exactly('Boas-vindas', 'Regra')
    end

    it 'is idempotent — a second call creates no duplicates' do
      post "/api/v1/accounts/#{account.id}/flows/import", headers: administrator.create_new_auth_token
      expect do
        post "/api/v1/accounts/#{account.id}/flows/import", headers: administrator.create_new_auth_token
      end.not_to change(Flow, :count)
      expect(response.parsed_body['summary']['skipped']).to eq(2)
    end

    it 'does not persist anything in dry_run mode but still reports the counts' do
      expect do
        post "/api/v1/accounts/#{account.id}/flows/import", params: { dry_run: true },
                                                            headers: administrator.create_new_auth_token
      end.not_to change(Flow, :count)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['dry_run']).to be(true)
      expect(response.parsed_body['summary']['macros']).to eq(1)
    end
  end
end
