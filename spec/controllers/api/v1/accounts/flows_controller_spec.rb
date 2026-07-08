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

  describe 'POST /api/v1/accounts/{account.id}/flows/{id}/simulate' do
    let(:flow) do
      create(:flow, account: account, created_by: administrator, visibility: :global,
                    definition: {
                      'nodes' => [
                        { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_message', 'action_params' => ['Olá {{contact.name}}'] }
                      ],
                      'edges' => []
                    })
    end

    it 'returns unauthorized when unauthenticated' do
      post "/api/v1/accounts/#{account.id}/flows/#{flow.id}/simulate"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the simulated steps WITHOUT effecting anything (no message, no logs, no run)' do
      conversation = create(:conversation, account: account)
      expect do
        post "/api/v1/accounts/#{account.id}/flows/#{flow.id}/simulate",
             params: { conversation_id: conversation.display_id },
             headers: administrator.create_new_auth_token, as: :json
      end.to not_change(Message, :count)
        .and(not_change(FlowStepLog, :count))
        .and(not_change(FlowRun, :count))

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['steps']).to be_an(Array)
      expect(body['steps'].first).to include('node_id' => 'n1', 'type' => 'action', 'action_name' => 'send_message')
      expect(body['steps'].first['would']).to be_present
      expect(body['conversation']['id']).to eq(conversation.display_id)
    end

    it 'falls back to the most recent conversation when none is given' do
      create(:conversation, account: account)
      post "/api/v1/accounts/#{account.id}/flows/#{flow.id}/simulate",
           headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['steps']).to be_present
    end

    it 'returns 422 with a stable code when the account has no conversation to simulate with' do
      post "/api/v1/accounts/#{account.id}/flows/#{flow.id}/simulate",
           headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('no_conversation')
    end

    it 'records the branch a condition takes, without executing anything' do
      status_condition = { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }
      branching = create(:flow, account: account, created_by: administrator, visibility: :global,
                                definition: {
                                  'nodes' => [
                                    { 'id' => 'c1', 'type' => 'condition', 'conditions' => [status_condition] },
                                    { 'id' => 'a1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['vip'] }
                                  ],
                                  'edges' => [{ 'from' => 'c1', 'to' => 'a1', 'branch' => 'true' }]
                                })
      create(:conversation, account: account, status: :open)
      post "/api/v1/accounts/#{account.id}/flows/#{branching.id}/simulate",
           headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      condition_step = body['steps'].find { |s| s['type'] == 'condition' }
      expect(condition_step['branch_key']).to eq('true')
      expect(body['branch_path'].first).to include('node_id' => 'c1', 'branch' => 'true')
    end

    it 'forbids simulating a flow the user cannot see' do
      agent = create(:user, account: account, role: :agent)
      private_flow = create(:flow, account: account, created_by: administrator, visibility: :personal)
      create(:conversation, account: account)
      post "/api/v1/accounts/#{account.id}/flows/#{private_flow.id}/simulate",
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/flows/{id}/logs' do
    it 'returns unauthorized when unauthenticated' do
      flow = create(:flow, account: account, created_by: administrator, visibility: :global)
      get "/api/v1/accounts/#{account.id}/flows/#{flow.id}/logs"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns only this flow's step logs, most recent first, with a meta count" do
      flow = create(:flow, account: account, created_by: administrator, visibility: :global)
      other_flow = create(:flow, account: account, created_by: administrator, visibility: :global)
      create(:flow_step_log, flow: flow, account: account, node_id: 'n1', created_at: 2.minutes.ago)
      create(:flow_step_log,
             flow: flow, account: account, node_id: 'n2', action_name: nil,
             status: :failed, error_code: 'action_failed', error_message: 'boom',
             duration_ms: 3, created_at: 1.minute.ago)
      create(:flow_step_log, flow: other_flow, account: account, node_id: 'x1')

      get "/api/v1/accounts/#{account.id}/flows/#{flow.id}/logs", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['payload'].length).to eq(2)
      expect(body['payload'].pluck('node_id')).to eq(%w[n2 n1]) # recent first
      failed = body['payload'].first
      expect(failed).to include('status' => 'failed', 'error_code' => 'action_failed', 'error_message' => 'boom', 'duration_ms' => 3)
      expect(body['meta']['total_count']).to eq(2)
    end

    it 'returns an empty payload when the flow never ran' do
      flow = create(:flow, account: account, created_by: administrator, visibility: :global)
      get "/api/v1/accounts/#{account.id}/flows/#{flow.id}/logs", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to eq([])
      expect(response.parsed_body['meta']['total_count']).to eq(0)
    end

    it 'forbids reading logs of a flow the user cannot see' do
      agent = create(:user, account: account, role: :agent)
      private_flow = create(:flow, account: account, created_by: administrator, visibility: :personal)
      get "/api/v1/accounts/#{account.id}/flows/#{private_flow.id}/logs", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/flows/{id}/stats' do
    let(:flow) { create(:flow, account: account, created_by: administrator, visibility: :global) }

    it 'returns unauthorized when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/flows/#{flow.id}/stats"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns per-node executions/failures with a pct relative to the busiest node' do
      create(:flow_node_stat, flow: flow, account: account, node_id: 'n1', executions: 100, failures: 0)
      create(:flow_node_stat, flow: flow, account: account, node_id: 'n2', executions: 38, failures: 4)

      get "/api/v1/accounts/#{account.id}/flows/#{flow.id}/stats", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['period']).to eq('all')
      expect(body['total_entries']).to eq(100)
      expect(body['nodes']['n1']).to eq('executions' => 100, 'failures' => 0, 'pct' => 100)
      expect(body['nodes']['n2']).to eq('executions' => 38, 'failures' => 4, 'pct' => 38)
    end

    it 'returns an empty node map when the flow has no stats yet' do
      get "/api/v1/accounts/#{account.id}/flows/#{flow.id}/stats", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['nodes']).to eq({})
      expect(response.parsed_body['total_entries']).to eq(0)
    end

    it 'ignores stats from other flows and non-lifetime periods' do
      other_flow = create(:flow, account: account, created_by: administrator, visibility: :global)
      create(:flow_node_stat, flow: flow, account: account, node_id: 'n1', executions: 10)
      create(:flow_node_stat, flow: flow, account: account, node_id: 'n1', period: '2026-07-08', executions: 3)
      create(:flow_node_stat, flow: other_flow, account: account, node_id: 'x1', executions: 99)

      get "/api/v1/accounts/#{account.id}/flows/#{flow.id}/stats", headers: administrator.create_new_auth_token
      expect(response.parsed_body['nodes'].keys).to contain_exactly('n1')
      expect(response.parsed_body['nodes']['n1']['executions']).to eq(10)
    end

    it 'forbids reading stats of a flow the user cannot see' do
      agent = create(:user, account: account, role: :agent)
      private_flow = create(:flow, account: account, created_by: administrator, visibility: :personal)
      get "/api/v1/accounts/#{account.id}/flows/#{private_flow.id}/stats", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
