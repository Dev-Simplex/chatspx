# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FlowRun, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:flow) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to belong_to(:contact).optional }
  end

  describe 'enum status' do
    it 'defines the lifecycle states' do
      expect(described_class.statuses).to eq('active' => 0, 'waiting' => 1, 'completed' => 2, 'failed' => 3)
    end
  end

  describe '.due' do
    let(:flow) { create(:flow) }

    it 'returns waiting runs whose wait_until has passed' do
      due = create(:flow_run, flow: flow, wait_until: 1.minute.ago, status: :waiting)
      create(:flow_run, flow: flow, wait_until: 1.hour.from_now, status: :waiting)
      create(:flow_run, flow: flow, wait_until: 1.minute.ago, status: :completed)

      expect(described_class.due).to contain_exactly(due)
    end
  end

  describe '#suspend!' do
    it 'parks the run at a node with a resume time' do
      run = create(:flow_run, status: :active, current_node_id: nil, wait_until: nil)

      run.suspend!(node_id: 'n5', wait_until: 10.minutes.from_now)

      expect(run.reload).to be_waiting
      expect(run.current_node_id).to eq('n5')
      expect(run.wait_until).to be_within(1.second).of(10.minutes.from_now)
    end
  end

  describe '#complete! / #finish!' do
    it 'marks completed and clears the resume pointers' do
      run = create(:flow_run, status: :waiting, current_node_id: 'n2', wait_until: 1.minute.ago)

      run.complete!

      expect(run.reload).to be_completed
      expect(run.current_node_id).to be_nil
      expect(run.wait_until).to be_nil
    end

    it 'finish! is an alias of complete!' do
      run = create(:flow_run, status: :waiting)
      run.finish!
      expect(run.reload).to be_completed
    end
  end

  describe '#fail!' do
    it 'marks failed and drops out of .due' do
      run = create(:flow_run, status: :waiting, wait_until: 1.minute.ago)

      run.fail!

      expect(run.reload).to be_failed
      expect(described_class.due).not_to include(run)
    end
  end

  describe 'partial unique index (one in-flight run per flow+conversation)' do
    let(:flow) { create(:flow) }
    let(:conversation) { create(:conversation, account: flow.account) }

    it 'rejects a second active|waiting run for the same flow+conversation' do
      create(:flow_run, flow: flow, conversation: conversation, status: :waiting)

      expect do
        create(:flow_run, flow: flow, conversation: conversation, status: :active)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'permits a fresh run once the previous one completed' do
      create(:flow_run, flow: flow, conversation: conversation, status: :completed)

      expect do
        create(:flow_run, flow: flow, conversation: conversation, status: :waiting)
      end.not_to raise_error
    end
  end
end
