# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FlowNodeStat, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:flow) }
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    subject { build(:flow_node_stat) }

    it { is_expected.to validate_presence_of(:node_id) }
    it { is_expected.to validate_presence_of(:period) }

    it 'is unique per (flow, node_id, period)' do
      existing = create(:flow_node_stat)
      dup = build(:flow_node_stat, flow: existing.flow, account: existing.account, node_id: existing.node_id, period: existing.period)
      expect(dup).not_to be_valid
    end

    it 'allows the same node_id across different flows' do
      first = create(:flow_node_stat, node_id: 'n1')
      other = build(:flow_node_stat, node_id: 'n1')
      expect(other).to be_valid
      expect(other.flow_id).not_to eq(first.flow_id)
    end

    it 'allows the same node_id across different periods of the same flow' do
      existing = create(:flow_node_stat, period: FlowNodeStat::ALL_TIME)
      daily = build(:flow_node_stat, flow: existing.flow, account: existing.account, node_id: existing.node_id, period: '2026-07-08')
      expect(daily).to be_valid
    end
  end

  describe 'scopes' do
    let(:flow) { create(:flow) }

    describe '.for_flow' do
      it 'returns only the given flow stats' do
        mine = create(:flow_node_stat, flow: flow, account: flow.account)
        create(:flow_node_stat)
        expect(described_class.for_flow(flow)).to contain_exactly(mine)
      end
    end

    describe '.all_time' do
      it 'returns only the lifetime (period all) rows' do
        lifetime = create(:flow_node_stat, flow: flow, account: flow.account, period: FlowNodeStat::ALL_TIME)
        create(:flow_node_stat, flow: flow, account: flow.account, node_id: 'n2', period: '2026-07-08')
        expect(described_class.for_flow(flow).all_time).to contain_exactly(lifetime)
      end
    end
  end
end
