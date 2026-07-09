# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flows::StatsRollupJob do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }

  def log(node_id, status: :success, flow_on: flow)
    create(:flow_step_log, flow: flow_on, account: flow_on.account, node_id: node_id, status: status)
  end

  def stat(node_id, flow_on: flow)
    FlowNodeStat.for_flow(flow_on).all_time.find_by(node_id: node_id)
  end

  it 'aggregates N executions of a node into a stat row with executions N' do
    5.times { log('n1') }
    described_class.perform_now
    expect(stat('n1').executions).to eq(5)
    expect(stat('n1').failures).to eq(0)
  end

  it 'counts every visited status as an execution (success + failed + skipped are all "reached")' do
    log('n1', status: :success)
    log('n1', status: :failed)
    log('n1', status: :skipped)
    described_class.perform_now
    expect(stat('n1').executions).to eq(3)
    expect(stat('n1').failures).to eq(1)
  end

  it 'aggregates each node of a flow independently' do
    3.times { log('n1') }
    log('n2')
    described_class.perform_now
    expect(stat('n1').executions).to eq(3)
    expect(stat('n2').executions).to eq(1)
  end

  it 'keeps stats of different flows separate' do
    other = create(:flow, account: account)
    2.times { log('n1') }
    log('n1', flow_on: other)
    described_class.perform_now
    expect(stat('n1').executions).to eq(2)
    expect(stat('n1', flow_on: other).executions).to eq(1)
  end

  it 'writes the lifetime period marker' do
    log('n1')
    described_class.perform_now
    expect(stat('n1').period).to eq(FlowNodeStat::ALL_TIME)
    expect(stat('n1').account_id).to eq(account.id)
  end

  it 'is idempotent — a second run leaves the same counts (SET, not increment)' do
    4.times { log('n1') }
    described_class.perform_now
    expect { described_class.perform_now }.not_to(change { stat('n1').reload.executions })
    expect(FlowNodeStat.for_flow(flow).all_time.count).to eq(1)
  end

  it 'refreshes an existing stat when new logs arrive' do
    2.times { log('n1') }
    described_class.perform_now
    expect(stat('n1').executions).to eq(2)

    3.times { log('n1') }
    described_class.perform_now
    expect(stat('n1').reload.executions).to eq(5)
  end

  it 'is a no-op when there are no step logs' do
    expect { described_class.perform_now }.not_to change(FlowNodeStat, :count)
  end
end
