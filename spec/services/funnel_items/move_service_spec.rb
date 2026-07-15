# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FunnelItems::MoveService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Pipeline', color: '#64748b') }
  let(:open_stage) { FunnelStage.create!(funnel: funnel, name: 'Open', automation_type: 'open', position: 0) }
  let(:resolved_stage) { FunnelStage.create!(funnel: funnel, name: 'Resolved', automation_type: 'resolved', position: 1) }

  describe '#perform' do
    it 'resolves conversation from resolved automation stage even without team' do
      conversation = create(:conversation, account: account, inbox: inbox, status: :open, team: nil)
      FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation)

      described_class.new(
        conversation: conversation,
        funnel: funnel,
        funnel_stage: resolved_stage,
        moved_by: agent
      ).perform

      expect(conversation.reload.status).to eq('resolved')
      expect(conversation.skip_team_required_for_resolution_validation).to eq(false)
    end

    it 'reopens conversation when moving to open automation stage' do
      team = create(:team, account: account)
      conversation = create(:conversation, :with_team, account: account, inbox: inbox, team: team, status: :resolved)
      FunnelItem.create!(funnel: funnel, funnel_stage: resolved_stage, conversation: conversation)

      described_class.new(
        conversation: conversation,
        funnel: funnel,
        funnel_stage: open_stage,
        moved_by: agent
      ).perform

      expect(conversation.reload.status).to eq('open')
    end
  end

  describe 'position placement (fractional indexing)' do
    def move(conversation, stage)
      described_class.new(conversation: conversation, funnel: funnel, funnel_stage: stage, moved_by: agent).perform
    end

    it 'places a new card at the top of the stage with a unique position (not the default 0)' do
      first = FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: create(:conversation, account: account, inbox: inbox),
                                 position: 1)

      placed = move(create(:conversation, account: account, inbox: inbox), open_stage)

      # Vai para o topo (menor position da coluna) e não colide com o card existente.
      expect(placed.position).to be < first.position
      expect(placed.position).to eq(FunnelItem.where(funnel_stage_id: open_stage.id).minimum(:position))
    end

    it 'gives distinct positions to several new cards in the same stage (no collision)' do
      3.times { move(create(:conversation, account: account, inbox: inbox), open_stage) }

      positions = FunnelItem.where(funnel_stage_id: open_stage.id).pluck(:position)
      expect(positions.uniq.size).to eq(positions.size)
    end

    it 'repositions a card to the top of the destination stage on a cross-stage move' do
      FunnelItem.create!(funnel: funnel, funnel_stage: resolved_stage, conversation: create(:conversation, account: account, inbox: inbox),
                         position: 5)
      conversation = create(:conversation, account: account, inbox: inbox)
      item = move(conversation, open_stage)

      moved = move(conversation, resolved_stage)

      top = FunnelItem.where(funnel_stage_id: resolved_stage.id).minimum(:position)
      expect(moved.id).to eq(item.id)
      expect(moved.position).to eq(top)
    end
  end
end
