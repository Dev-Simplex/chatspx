require 'rails_helper'

RSpec.describe Flows::ExecutionJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account) }
  let(:node) { { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['manual'] } }
  let(:flow) do
    create(:flow, account: account, trigger_type: :manual, definition: { 'nodes' => [node], 'edges' => [] })
  end

  it 'runs the flow on each conversation with the user as actor' do
    described_class.perform_now(flow.id, conversation_ids: [conversation.display_id], user_id: user.id)
    expect(conversation.reload.label_list).to include('manual')
  end

  it 'is a no-op for a missing flow' do
    expect { described_class.perform_now(0, conversation_ids: [conversation.display_id], user_id: user.id) }.not_to raise_error
  end

  it 'is a no-op for a missing user' do
    expect { described_class.perform_now(flow.id, conversation_ids: [conversation.display_id], user_id: 0) }.not_to raise_error
  end

  it 'is a no-op when no conversation matches' do
    expect { described_class.perform_now(flow.id, conversation_ids: [], user_id: user.id) }.not_to raise_error
  end
end
