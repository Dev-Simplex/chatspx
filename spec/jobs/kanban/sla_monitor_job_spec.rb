# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kanban::SlaMonitorJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aguardando', position: 0) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:automation) do
    FunnelAutomation.create!(
      funnel: funnel, funnel_stage: stage, name: 'SLA 24h',
      trigger: { 'event' => 'time_in_stage', 'hours' => 24 }, conditions: [],
      actions: [{ 'type' => 'tag', 'labels' => ['atrasado'] }]
    )
  end

  def item_aged(hours_ago)
    item = FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: conversation)
    item.update_column(:moved_at, hours_ago.hours.ago)
    item
  end

  it 'fires for a card past the budget' do
    item_aged(30)
    described_class.perform_now
    expect(conversation.reload.label_list).to include('atrasado')
  end

  it 'does not fire for a card still within the budget' do
    item_aged(2)
    described_class.perform_now
    expect(conversation.reload.label_list).not_to include('atrasado')
  end

  it 'is idempotent — fires once per stay even across runs' do
    item_aged(30)
    described_class.perform_now
    conversation.reload.update!(custom_attributes: conversation.custom_attributes.merge('probe' => '1'))
    # Remove the label to detect a second (unwanted) fire.
    conversation.update_labels([])
    described_class.perform_now
    expect(conversation.reload.label_list).not_to include('atrasado')
  end

  it 'fires again after the card re-enters the stage (moved_at changes)' do
    item = item_aged(30)
    described_class.perform_now
    conversation.update_labels([])
    # Simulate a fresh, already-overdue stay.
    item.update_column(:moved_at, 30.hours.ago)
    described_class.perform_now
    expect(conversation.reload.label_list).to include('atrasado')
  end
end
