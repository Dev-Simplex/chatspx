# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FlowStepLog, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:flow) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:conversation).optional }
    it { is_expected.to belong_to(:flow_run).optional }
  end

  describe 'enum status' do
    it 'defines success/failed/skipped' do
      expect(described_class.statuses).to eq('success' => 0, 'failed' => 1, 'skipped' => 2)
    end
  end

  describe 'scopes' do
    let(:flow) { create(:flow) }

    describe '.recent' do
      it 'orders the most-recent step first' do
        older = create(:flow_step_log, flow: flow, created_at: 2.hours.ago)
        newer = create(:flow_step_log, flow: flow, created_at: 1.minute.ago)

        expect(described_class.recent.to_a).to eq([newer, older])
      end
    end

    describe '.failed (provided by the status enum)' do
      it 'returns only failed steps' do
        failed = create(:flow_step_log, flow: flow, status: :failed)
        create(:flow_step_log, flow: flow, status: :success)
        create(:flow_step_log, flow: flow, status: :skipped)

        expect(described_class.failed).to contain_exactly(failed)
      end
    end

    describe '.for_flow / .for_conversation' do
      it 'filters by flow' do
        mine = create(:flow_step_log, flow: flow)
        create(:flow_step_log)

        expect(described_class.for_flow(flow)).to contain_exactly(mine)
      end

      it 'filters by conversation' do
        conversation = create(:conversation, account: flow.account)
        mine = create(:flow_step_log, flow: flow, conversation: conversation)
        create(:flow_step_log, flow: flow)

        expect(described_class.for_conversation(conversation)).to contain_exactly(mine)
      end
    end
  end
end
