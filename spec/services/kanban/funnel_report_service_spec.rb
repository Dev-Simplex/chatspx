# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kanban::FunnelReportService do
  subject(:report) { described_class.new(funnel: funnel).perform }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:stage_open) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }
  let(:stage_sla) do
    stage = FunnelStage.create!(funnel: funnel, name: 'Aguardando', position: 1)
    stage.update!(settings: { 'sla_hours' => 24 })
    stage
  end

  def place(conversation, stage, moved_at: nil)
    item = FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: conversation)
    item.update_column(:moved_at, moved_at) if moved_at
    item
  end

  it 'reports totals: cards, status breakdown, unassigned' do
    c1 = create(:conversation, account: account, inbox: inbox, status: :open, assignee: agent)
    c2 = create(:conversation, account: account, inbox: inbox, status: :open)
    place(c1, stage_open)
    place(c2, stage_open)

    expect(report[:totals][:cards]).to eq(2)
    expect(report[:totals][:by_status]).to include('open' => 2)
    expect(report[:totals][:unassigned]).to eq(1)
  end

  it 'computes per-stage counts and overdue against the stage SLA' do
    fresh = create(:conversation, account: account, inbox: inbox)
    stale = create(:conversation, account: account, inbox: inbox)
    place(fresh, stage_sla, moved_at: 2.hours.ago)
    place(stale, stage_sla, moved_at: 30.hours.ago)

    sla_row = report[:stages].find { |s| s[:id] == stage_sla.id }
    expect(sla_row[:count]).to eq(2)
    expect(sla_row[:sla_hours]).to eq(24)
    expect(sla_row[:overdue]).to eq(1)
    expect(sla_row[:avg_age_seconds]).to be > 0
  end

  it 'reports workload per assignee' do
    c1 = create(:conversation, account: account, inbox: inbox, assignee: agent)
    c2 = create(:conversation, account: account, inbox: inbox, assignee: agent)
    place(c1, stage_open)
    place(c2, stage_open)

    row = report[:workload].find { |w| w[:assignee_id] == agent.id }
    expect(row[:count]).to eq(2)
    expect(row[:name]).to be_present
  end
end
