# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kanban::AutomationEngineService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:stage_wait) { FunnelStage.create!(funnel: funnel, name: 'Aguardando', position: 0) }
  let(:stage_urgent) { FunnelStage.create!(funnel: funnel, name: 'Urgente', position: 1) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, priority: :high) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def place(stage)
    FunnelItems::MoveService.new(conversation: conversation, funnel: funnel, funnel_stage: stage, moved_by: nil).perform
  end

  describe 'item_entered_stage trigger' do
    it 'runs a matching rule: assign + tag when a card enters the stage' do
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage_wait, name: 'Triagem',
        trigger: { 'event' => 'item_entered_stage' },
        conditions: [{ 'field' => 'priority', 'op' => 'eq', 'value' => 'high' }],
        actions: [{ 'type' => 'assign', 'assignee_id' => agent.id }, { 'type' => 'tag', 'labels' => ['quente'] }]
      )

      place(stage_wait)

      expect(conversation.reload.assignee_id).to eq(agent.id)
      expect(conversation.label_list).to include('quente')
    end

    it 'does not run when conditions fail' do
      conversation.update!(priority: :low)
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage_wait, name: 'Só alta',
        trigger: { 'event' => 'item_entered_stage' },
        conditions: [{ 'field' => 'priority', 'op' => 'eq', 'value' => 'high' }],
        actions: [{ 'type' => 'tag', 'labels' => ['quente'] }]
      )

      place(stage_wait)

      expect(conversation.reload.label_list).not_to include('quente')
    end

    it 'only fires for its scoped stage' do
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage_urgent, name: 'Só urgente',
        trigger: { 'event' => 'item_entered_stage' }, conditions: [],
        actions: [{ 'type' => 'tag', 'labels' => ['urg'] }]
      )

      place(stage_wait)
      expect(conversation.reload.label_list).not_to include('urg')

      place(stage_urgent)
      expect(conversation.reload.label_list).to include('urg')
    end

    it 'executes a move action (escalation) into another stage' do
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage_wait, name: 'Escalar',
        trigger: { 'event' => 'item_entered_stage' }, conditions: [],
        actions: [{ 'type' => 'move', 'stage_id' => stage_urgent.id }]
      )

      place(stage_wait)

      item = FunnelItem.find_by(conversation: conversation, funnel: funnel)
      expect(item.funnel_stage_id).to eq(stage_urgent.id)
    end
  end

  describe 'reentrancy guard' do
    it 'caps a ping-pong move chain instead of looping forever' do
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage_wait, name: 'A→B',
        trigger: { 'event' => 'item_entered_stage' }, conditions: [],
        actions: [{ 'type' => 'move', 'stage_id' => stage_urgent.id }]
      )
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage_urgent, name: 'B→A',
        trigger: { 'event' => 'item_entered_stage' }, conditions: [],
        actions: [{ 'type' => 'move', 'stage_id' => stage_wait.id }]
      )

      expect { place(stage_wait) }.not_to raise_error
      # The depth counter is always unwound back to nil after the chain settles.
      expect(Current.funnel_automation_depth).to be_nil.or eq(0)
    end
  end

  describe 'best-effort execution' do
    it 'never raises when an action references a missing agent' do
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage_wait, name: 'Bad assign',
        trigger: { 'event' => 'item_entered_stage' }, conditions: [],
        actions: [{ 'type' => 'assign', 'assignee_id' => 999_999 }, { 'type' => 'tag', 'labels' => ['ok'] }]
      )

      expect { place(stage_wait) }.not_to raise_error
      # The good action still ran despite the bad one.
      expect(conversation.reload.label_list).to include('ok')
    end
  end
end
