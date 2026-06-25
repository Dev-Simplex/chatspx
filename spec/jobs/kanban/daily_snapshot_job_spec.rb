# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kanban::DailySnapshotJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }

  it 'captures one snapshot per funnel for today' do
    conversation = create(:conversation, account: account, inbox: inbox)
    FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: conversation)

    expect { described_class.perform_now }.to change { funnel.funnel_metric_snapshots.count }.by(1)

    snapshot = funnel.funnel_metric_snapshots.find_by(captured_on: Date.current)
    expect(snapshot.metrics.dig('totals', 'cards')).to eq(1)
    expect(snapshot.metrics['stages']).to be_an(Array)
  end

  it 'is idempotent — re-running refreshes today\'s row, not adds one' do
    funnel # ensure the funnel exists before the first run
    described_class.perform_now
    expect { described_class.perform_now }.not_to(change { funnel.funnel_metric_snapshots.count })
  end
end
