require 'rails_helper'

RSpec.describe Flows::SimulationService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  after { Current.reset }

  def simulate(definition, actor: nil)
    flow = create(:flow, account: account, definition: definition)
    described_class.new(flow: flow, conversation: conversation, actor: actor).perform
  end

  def action_node(id, action_name = 'add_label', params = ['vip'])
    { 'id' => id, 'type' => 'action', 'action_name' => action_name, 'action_params' => params }
  end

  def status_condition(id, value)
    { 'id' => id, 'type' => 'condition',
      'conditions' => [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => [value], 'query_operator' => nil }] }
  end

  # ── INOCUIDADE POR CONSTRUÇÃO ────────────────────────────────────────────────────────────
  describe 'inocuidade — a simulação NÃO efetiva nada' do
    let(:trigger_condition_action) do
      { 'nodes' => [{ 'id' => 't1', 'type' => 'trigger' }, status_condition('c1', 'open'), action_node('yes', 'send_message', ['Olá'])],
        'edges' => [{ 'from' => 't1', 'to' => 'c1' }, { 'from' => 'c1', 'to' => 'yes', 'branch' => 'true' }] }
    end

    it 'never instantiates the Flows::ActionService (execute is unreachable by construction)' do
      expect(Flows::ActionService).not_to receive(:new)
      simulate(trigger_condition_action)
    end

    it 'never calls Flows::ActionService#execute' do
      expect_any_instance_of(Flows::ActionService).not_to receive(:execute) # rubocop:disable RSpec/AnyInstance
      simulate(trigger_condition_action)
    end

    it 'sends no message and mutates no conversation state (send_message + add_label)' do
      definition = { 'nodes' => [action_node('n1', 'send_message', ['oi']), action_node('n2', 'add_label', ['vip'])],
                     'edges' => [{ 'from' => 'n1', 'to' => 'n2' }] }
      expect { simulate(definition) }.not_to change(Message, :count)
      expect(conversation.reload.label_list).to be_empty
    end

    it 'writes no attribute for a set_attribute node' do
      attr_params = [{ 'target' => 'conversation', 'key' => 'plano', 'value' => 'ouro' }]
      simulate({ 'nodes' => [action_node('n1', 'set_attribute', attr_params)], 'edges' => [] })
      expect(conversation.reload.custom_attributes).not_to include('plano')
    end

    it 'persists nothing: no FlowStepLog and no FlowRun' do
      expect { simulate(trigger_condition_action) }.to not_change(FlowStepLog, :count).and not_change(FlowRun, :count)
    end
  end

  # ── CAMINHO PERCORRIDO + DESCRIÇÃO ───────────────────────────────────────────────────────
  describe 'trigger → condition(true) → action' do
    let(:result) do
      conversation.update!(status: :open)
      conversation.contact.update!(name: 'joão silva')
      simulate({ 'nodes' => [{ 'id' => 't1', 'type' => 'trigger' }, status_condition('c1', 'open'),
                             action_node('yes', 'send_message', ['Olá {{contact.name}}']), action_node('no', 'add_label', ['nope'])],
                 'edges' => [{ 'from' => 't1', 'to' => 'c1' },
                             { 'from' => 'c1', 'to' => 'yes', 'branch' => 'true' },
                             { 'from' => 'c1', 'to' => 'no', 'branch' => 'false' }] })
    end

    it 'walks the true branch in order (trigger, condition, action)' do
      expect(result.steps.map { |s| s[:node_id] }).to eq(%w[t1 c1 yes])
    end

    it 'records the condition decision in the branch_path' do
      expect(result.branch_path).to eq([{ node_id: 'c1', type: 'condition', branch: 'true' }])
    end

    it 'describes the action node (would + resolved Liquid params) without executing it' do
      action_step = result.steps.last
      expect(action_step).to include(type: 'action', action_name: 'send_message')
      expect(action_step[:params_resolved]).to eq(['Olá João Silva']) # Liquid resolvido read-only
      expect(action_step[:would]).to eq('Enviaria a mensagem: Olá João Silva')
    end
  end

  it 'follows the false branch when the condition does not match' do
    conversation.update!(status: :open)
    result = simulate(
      { 'nodes' => [status_condition('c1', 'resolved'), action_node('yes', 'add_label', ['matched']), action_node('no', 'add_label', ['unmatched'])],
        'edges' => [{ 'from' => 'c1', 'to' => 'yes', 'branch' => 'true' }, { 'from' => 'c1', 'to' => 'no', 'branch' => 'false' }] }
    )
    expect(result.steps.map { |s| s[:node_id] }).to eq(%w[c1 no])
    expect(result.branch_path.first[:branch]).to eq('false')
    expect(result.steps.last[:params_resolved]).to eq(['unmatched'])
  end

  # ── ROUTER (first-match) ─────────────────────────────────────────────────────────────────
  describe 'router first-match branching' do
    def route(key, attribute_key, value)
      condition = { 'attribute_key' => attribute_key, 'filter_operator' => 'equal_to', 'values' => [value], 'query_operator' => nil }
      { 'key' => key, 'conditions' => [condition] }
    end

    def router_definition(routes)
      { 'nodes' => [{ 'id' => 'r1', 'type' => 'router', 'routes' => routes, 'fallback_key' => 'fallback' },
                    action_node('a_status', 'add_label', ['status_route']),
                    action_node('a_priority', 'add_label', ['priority_route']),
                    action_node('a_else', 'add_label', ['fell_back'])],
        'edges' => [{ 'from' => 'r1', 'to' => 'a_status', 'branch' => 'by_status' },
                    { 'from' => 'r1', 'to' => 'a_priority', 'branch' => 'by_priority' },
                    { 'from' => 'r1', 'to' => 'a_else', 'branch' => 'fallback' }] }
    end

    it 'chooses the FIRST matching route even when a later route also matches' do
      conversation.update!(status: :open, priority: :urgent) # both routes would match
      result = simulate(router_definition([route('by_status', 'status', 'open'), route('by_priority', 'priority', 'urgent')]))
      expect(result.branch_path.first).to eq({ node_id: 'r1', type: 'router', branch: 'by_status' })
      expect(result.steps.map { |s| s[:node_id] }).to eq(%w[r1 a_status])
    end

    it 'skips a non-matching route and takes the next matching one' do
      conversation.update!(status: :open, priority: :urgent)
      result = simulate(router_definition([route('by_status', 'status', 'resolved'), route('by_priority', 'priority', 'urgent')]))
      expect(result.branch_path.first[:branch]).to eq('by_priority')
      expect(result.steps.last[:params_resolved]).to eq(['priority_route'])
    end

    it 'takes the fallback branch when no route matches' do
      conversation.update!(status: :open, priority: :low)
      result = simulate(router_definition([route('by_status', 'status', 'resolved'), route('by_priority', 'priority', 'urgent')]))
      expect(result.branch_path.first[:branch]).to eq('fallback')
      expect(result.steps.last[:params_resolved]).to eq(['fell_back'])
    end
  end

  # ── WAIT (não suspende) ──────────────────────────────────────────────────────────────────
  describe 'wait nodes are traversed, not suspended' do
    let(:wait_definition) do
      { 'nodes' => [action_node('n1', 'add_label', ['before']),
                    { 'id' => 'w1', 'type' => 'wait', 'wait' => { 'value' => 5, 'unit' => 'minutes' } },
                    action_node('n2', 'add_label', ['after'])],
        'edges' => [{ 'from' => 'n1', 'to' => 'w1' }, { 'from' => 'w1', 'to' => 'n2' }] }
    end

    it 'creates no FlowRun and walks the WHOLE path past the wait' do
      result = nil
      expect { result = simulate(wait_definition) }.not_to change(FlowRun, :count)
      expect(result.steps.map { |s| s[:node_id] }).to eq(%w[n1 w1 n2])
      expect(result.steps.last[:node_id]).to eq('n2') # o nó DEPOIS do wait foi alcançado
    end

    it 'records what the wait would do' do
      wait_step = simulate(wait_definition).steps.find { |s| s[:type] == 'wait' }
      expect(wait_step[:would]).to eq('aguardaria 5 minutes')
      expect(wait_step[:params_resolved]).to include('value' => 5, 'unit' => 'minutes')
    end
  end

  # ── NÃO-REGRESSÃO: o mesmo grafo, executado DE VERDADE, ainda efetiva ────────────────────
  it 'the same flow run for real (dry_run:false) still applies the action' do
    definition = { 'nodes' => [action_node('n1', 'add_label', ['real'])], 'edges' => [] }
    flow = create(:flow, account: account, definition: definition)
    Flows::RunnerService.new(flow: flow, conversation: conversation).perform
    expect(conversation.reload.label_list).to include('real')
  end
end
