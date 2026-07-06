require 'rails_helper'

RSpec.describe Flows::RunnerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  after { Current.reset }

  def run(definition, actor: nil)
    flow = create(:flow, account: account, definition: definition)
    described_class.new(flow: flow, conversation: conversation, actor: actor).perform
  end

  def action_node(id, label)
    { 'id' => id, 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [label] }
  end

  def status_condition(id, value)
    { 'id' => id, 'type' => 'condition',
      'conditions' => [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => [value], 'query_operator' => nil }] }
  end

  it 'walks a linear chain of action nodes in order' do
    definition = {
      'nodes' => [action_node('n1', 'a'), action_node('n2', 'b')],
      'edges' => [{ 'from' => 'n1', 'to' => 'n2' }]
    }
    run(definition)
    expect(conversation.reload.label_list).to include('a', 'b')
  end

  it 'starts at the root even when a trigger node leads the chain' do
    definition = {
      'nodes' => [{ 'id' => 't1', 'type' => 'trigger' }, action_node('n1', 'reached')],
      'edges' => [{ 'from' => 't1', 'to' => 'n1' }]
    }
    run(definition)
    expect(conversation.reload.label_list).to include('reached')
  end

  it 'follows the true branch when the condition matches' do
    conversation.update!(status: :open)
    definition = {
      'nodes' => [status_condition('c1', 'open'), action_node('yes', 'matched'), action_node('no', 'unmatched')],
      'edges' => [
        { 'from' => 'c1', 'to' => 'yes', 'branch' => 'true' },
        { 'from' => 'c1', 'to' => 'no', 'branch' => 'false' }
      ]
    }
    run(definition)
    expect(conversation.reload.label_list).to include('matched')
    expect(conversation.reload.label_list).not_to include('unmatched')
  end

  it 'follows the false branch when the condition does not match' do
    conversation.update!(status: :open)
    definition = {
      'nodes' => [status_condition('c1', 'resolved'), action_node('yes', 'matched'), action_node('no', 'unmatched')],
      'edges' => [
        { 'from' => 'c1', 'to' => 'yes', 'branch' => 'true' },
        { 'from' => 'c1', 'to' => 'no', 'branch' => 'false' }
      ]
    }
    run(definition)
    expect(conversation.reload.label_list).to include('unmatched')
    expect(conversation.reload.label_list).not_to include('matched')
  end

  it 'stops after MAX_STEPS on a cyclic graph (no infinite loop)' do
    stub_const("#{described_class}::MAX_STEPS", 5)
    definition = { 'nodes' => [action_node('n1', 'x')], 'edges' => [{ 'from' => 'n1', 'to' => 'n1' }] }
    flow = create(:flow, account: account, definition: definition)
    action_service = instance_spy(Flows::ActionService)
    allow(Flows::ActionService).to receive(:new).and_return(action_service)
    described_class.new(flow: flow, conversation: conversation).perform
    expect(action_service).to have_received(:execute).exactly(5).times
  end

  it 'resets Current after the run' do
    run({ 'nodes' => [action_node('n1', 'a')], 'edges' => [] })
    expect(Current.executed_by).to be_nil
    expect(Current.flow_depth).to be_nil
  end

  # Paridade com o macro na reatribuição é garantida NATIVAMENTE pelo Conversation
  # (AssignmentHandler#mark_conversation_unread_on_assignment_change, after_commit) — o
  # Runner não replica. Aqui só confirmamos que o modo manual de fato reatribui.
  it 'reassigns the conversation in manual mode' do
    agent = create(:user, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    conversation.update!(assignee: nil)
    definition = { 'nodes' => [{ 'id' => 'n1', 'type' => 'action', 'action_name' => 'assign_agent', 'action_params' => [agent.id] }], 'edges' => [] }
    flow = create(:flow, account: account, definition: definition)
    described_class.new(flow: flow, conversation: conversation, actor: agent).perform
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end
end
