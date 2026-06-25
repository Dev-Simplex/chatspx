# frozen_string_literal: true

require 'rails_helper'

# Follow-up drip (A3): the enroll_in_sequence automation action.
RSpec.describe Kanban::AutomationEngineService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Novo', position: 0) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:sequence) { create(:message_sequence, :with_steps, account: account) }

  before { create(:user, account: account, role: :administrator) }

  describe 'enroll_in_sequence action' do
    it 'enrolls the conversation when a card enters the stage' do
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage, name: 'Inscreve',
        trigger: { 'event' => 'item_entered_stage' }, conditions: [],
        actions: [{ 'type' => 'enroll_in_sequence', 'sequence_id' => sequence.id }]
      )

      expect do
        FunnelItems::MoveService.new(
          conversation: conversation, funnel: funnel, funnel_stage: stage, moved_by: nil
        ).perform
      end.to change { MessageSequenceEnrollment.where(conversation: conversation).count }.by(1)
    end

    it 'is a no-op when the referenced sequence does not exist' do
      FunnelAutomation.create!(
        funnel: funnel, funnel_stage: stage, name: 'Inscreve fantasma',
        trigger: { 'event' => 'item_entered_stage' }, conditions: [],
        actions: [{ 'type' => 'enroll_in_sequence', 'sequence_id' => 0 }]
      )

      expect do
        FunnelItems::MoveService.new(
          conversation: conversation, funnel: funnel, funnel_stage: stage, moved_by: nil
        ).perform
      end.not_to change(MessageSequenceEnrollment, :count)
    end
  end
end
