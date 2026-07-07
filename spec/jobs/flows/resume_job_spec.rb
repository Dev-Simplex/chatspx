# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flows::ResumeJob do
  let(:account) { create(:account) }

  after { Current.reset }

  def wait_flow
    create(:flow, account: account, definition: {
             'nodes' => [
               { 'id' => 'w1', 'type' => 'wait', 'wait' => { 'value' => 5, 'unit' => 'minutes' } },
               { 'id' => 'n2', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['after'] }
             ],
             'edges' => [{ 'from' => 'w1', 'to' => 'n2' }]
           })
  end

  it 'resumes due runs and leaves future ones waiting' do
    flow = wait_flow
    due = create(:flow_run, flow: flow, conversation: create(:conversation, account: account),
                            current_node_id: 'n2', wait_until: 1.minute.ago, status: :waiting)
    future = create(:flow_run, flow: flow, conversation: create(:conversation, account: account),
                               current_node_id: 'n2', wait_until: 1.hour.from_now, status: :waiting)

    described_class.perform_now

    expect(due.reload).to be_completed
    expect(future.reload).to be_waiting
  end
end
