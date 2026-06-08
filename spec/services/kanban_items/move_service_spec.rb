# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KanbanItems::MoveService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:kanban) { Kanban.create!(account: account, name: 'Pipeline', color: '#64748b') }
  let(:open_stage) { KanbanStage.create!(kanban: kanban, name: 'Open', automation_type: 'open', position: 0) }
  let(:resolved_stage) { KanbanStage.create!(kanban: kanban, name: 'Resolved', automation_type: 'resolved', position: 1) }

  describe '#perform' do
    it 'resolves conversation from resolved automation stage even without team' do
      conversation = create(:conversation, account: account, inbox: inbox, status: :open, team: nil)
      KanbanItem.create!(kanban: kanban, kanban_stage: open_stage, conversation: conversation)

      described_class.new(
        conversation: conversation,
        kanban: kanban,
        kanban_stage: resolved_stage,
        moved_by: agent
      ).perform

      expect(conversation.reload.status).to eq('resolved')
      expect(conversation.skip_team_required_for_resolution_validation).to be(false)
    end

    it 'reopens conversation when moving to open automation stage' do
      team = create(:team, account: account)
      conversation = create(:conversation, :with_team, account: account, inbox: inbox, team: team, status: :resolved)
      KanbanItem.create!(kanban: kanban, kanban_stage: resolved_stage, conversation: conversation)

      described_class.new(
        conversation: conversation,
        kanban: kanban,
        kanban_stage: open_stage,
        moved_by: agent
      ).perform

      expect(conversation.reload.status).to eq('open')
    end
  end
end
