# frozen_string_literal: true

require 'rails_helper'

# Step observability (FlowStepLog) added on top of the walker. Kept in its own file so the
# non-regression baseline in runner_service_spec.rb stays untouched.
RSpec.describe Flows::RunnerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  after { Current.reset }

  def run(definition, actor: nil)
    flow = create(:flow, account: account, definition: definition)
    described_class.new(flow: flow, conversation: conversation, actor: actor).perform
    flow
  end

  def action_node(id, label)
    { 'id' => id, 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [label] }
  end

  def status_condition(id, value)
    { 'id' => id, 'type' => 'condition',
      'conditions' => [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => [value], 'query_operator' => nil }] }
  end

  it 'writes one success log per executed node (2 nodes → 2 success logs)' do
    flow = run({
                 'nodes' => [action_node('n1', 'a'), action_node('n2', 'b')],
                 'edges' => [{ 'from' => 'n1', 'to' => 'n2' }]
               })

    logs = FlowStepLog.where(flow: flow).order(:node_id)
    expect(logs.count).to eq(2)
    expect(logs.map(&:node_id)).to eq(%w[n1 n2])
    expect(logs.map(&:status).uniq).to eq(['success'])
    expect(logs.map(&:action_name).uniq).to eq(['add_label'])
    expect(logs.map(&:conversation_id).uniq).to eq([conversation.id])
    expect(logs.map(&:duration_ms)).to all(be >= 0)
  end

  it 'records a failed log with a typed error_code (unknown_action) when a node raises' do
    # save!(validate: false) bypasses the model action-name allowlist so we can force a real
    # runtime dispatch failure (NoMethodError → mapped to unknown_action).
    boom = { 'id' => 'boom', 'type' => 'action', 'action_name' => 'nonexistent_action', 'action_params' => [] }
    flow = build(:flow, account: account, definition: { 'nodes' => [boom], 'edges' => [] })
    flow.save!(validate: false)

    described_class.new(flow: flow, conversation: conversation).perform

    log = FlowStepLog.find_by(flow: flow, node_id: 'boom')
    expect(log).to be_failed
    expect(log.error_code).to eq('unknown_action')
    expect(log.error_message).to be_present
  end

  it 'records the true branch a condition took in branch_key' do
    conversation.update!(status: :open)
    flow = run({
                 'nodes' => [status_condition('c1', 'open'), action_node('yes', 'matched')],
                 'edges' => [{ 'from' => 'c1', 'to' => 'yes', 'branch' => 'true' }]
               })

    cond = FlowStepLog.find_by(flow: flow, node_id: 'c1')
    expect(cond).to be_success
    expect(cond.branch_key).to eq('true')
    expect(cond.metadata['node_type']).to eq('condition')
  end

  it 'records the false branch when the condition does not match' do
    conversation.update!(status: :open)
    flow = run({
                 'nodes' => [status_condition('c1', 'resolved'), action_node('no', 'x')],
                 'edges' => [{ 'from' => 'c1', 'to' => 'no', 'branch' => 'false' }]
               })

    expect(FlowStepLog.find_by(flow: flow, node_id: 'c1').branch_key).to eq('false')
  end

  it 'records a skipped log with the typed reason for a guarded no-op (send_template)' do
    # A non-WhatsApp inbox makes send_template skip with the typed reason.
    flow = run({
                 'nodes' => [{ 'id' => 't1', 'type' => 'action', 'action_name' => 'send_template',
                               'action_params' => [{ 'name' => 'x', 'language' => 'en' }] }],
                 'edges' => []
               })

    log = FlowStepLog.find_by(flow: flow, node_id: 't1')
    expect(log).to be_skipped
    expect(log.error_code).to eq('inbox_not_whatsapp')
    expect(log.error_message).to be_present
  end

  it 'logs a failing condition as failed (generic) and re-raises to preserve behavior' do
    flow = create(:flow, account: account, definition: { 'nodes' => [status_condition('c1', 'open')], 'edges' => [] })
    filter = instance_double(AutomationRules::ConditionsFilterService)
    allow(AutomationRules::ConditionsFilterService).to receive(:new).and_return(filter)
    allow(filter).to receive(:perform).and_raise(StandardError, 'kaboom')

    expect do
      described_class.new(flow: flow, conversation: conversation).perform
    end.to raise_error(StandardError, 'kaboom')

    log = FlowStepLog.find_by(flow: flow, node_id: 'c1')
    expect(log).to be_failed
    expect(log.error_code).to eq('generic')
  end

  it 'is best-effort: a logging failure never breaks the walk' do
    allow(FlowStepLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new('boom'))

    expect { run({ 'nodes' => [action_node('n1', 'a')], 'edges' => [] }) }.not_to raise_error
    expect(conversation.reload.label_list).to include('a') # the action itself still ran
  end
end
