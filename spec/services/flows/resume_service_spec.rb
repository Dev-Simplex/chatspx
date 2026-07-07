# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flows::ResumeService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  after { Current.reset }

  # A flow that waits, then labels the conversation — so we can assert the post-wait
  # branch only runs once the run is resumed.
  def wait_flow(after_label: 'after')
    create(:flow, account: account, definition: {
             'nodes' => [
               { 'id' => 'w1', 'type' => 'wait', 'wait' => { 'value' => 5, 'unit' => 'minutes' } },
               { 'id' => 'n2', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [after_label] }
             ],
             'edges' => [{ 'from' => 'w1', 'to' => 'n2' }]
           })
  end

  def waiting_run(flow, wait_until:, status: :waiting)
    create(:flow_run, flow: flow, conversation: conversation,
                      current_node_id: 'n2', wait_until: wait_until, status: status)
  end

  describe '#perform' do
    it 'resumes a due run from the stored node and completes it' do
      run = waiting_run(wait_flow, wait_until: 1.minute.ago)

      described_class.new(flow_run: run).perform

      expect(conversation.reload.label_list).to include('after')
      expect(run.reload).to be_completed
      expect(run.current_node_id).to be_nil
    end

    it 'does not resume a run whose wait_until is still in the future' do
      run = waiting_run(wait_flow, wait_until: 1.hour.from_now)

      described_class.new(flow_run: run).perform

      expect(conversation.reload.label_list).not_to include('after')
      expect(run.reload).to be_waiting
    end

    it 'is reentrant — an already-completed run is left untouched' do
      run = waiting_run(wait_flow, wait_until: 1.minute.ago, status: :completed)

      expect do
        described_class.new(flow_run: run).perform
      end.not_to(change { conversation.reload.label_list })
    end

    it 'marks the run failed when the resume raises (poison run stops retrying)' do
      run = waiting_run(wait_flow, wait_until: 1.minute.ago)
      allow(Flows::RunnerService).to receive(:new).and_raise(StandardError, 'boom')

      # Does not raise (swallowed best-effort), and the run is marked failed.
      expect { described_class.new(flow_run: run).perform }.not_to raise_error
      expect(run.reload).to be_failed
    end
  end
end
