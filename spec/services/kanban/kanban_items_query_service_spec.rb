# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kanban::KanbanItemsQueryService do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
    let(:kanban) { Kanban.create!(account: account, name: 'Geral', color: '#94a3b8') }
    let(:open_stage) { KanbanStage.create!(kanban: kanban, name: 'Abertos', automation_type: 'open', position: 0) }
    let(:resolved_stage) { KanbanStage.create!(kanban: kanban, name: 'Resolvidos', automation_type: 'resolved', position: 1) }

    let!(:conversation_1) { create(:conversation, account: account, inbox: inbox, status: :open, last_activity_at: 3.minutes.ago) }
    let!(:conversation_2) { create(:conversation, account: account, inbox: inbox, status: :open, last_activity_at: 2.minutes.ago) }
    let!(:conversation_3) { create(:conversation, account: account, inbox: inbox, status: :open, last_activity_at: 1.minute.ago) }
    let!(:conversation_resolved) { create(:conversation, account: account, inbox: inbox, status: :open, last_activity_at: 4.minutes.ago) }

    let!(:item_1) { KanbanItem.create!(kanban: kanban, kanban_stage: open_stage, conversation: conversation_1) }
    let!(:item_2) { KanbanItem.create!(kanban: kanban, kanban_stage: open_stage, conversation: conversation_2) }
    let!(:item_3) { KanbanItem.create!(kanban: kanban, kanban_stage: open_stage, conversation: conversation_3) }
    let!(:item_resolved) { KanbanItem.create!(kanban: kanban, kanban_stage: resolved_stage, conversation: conversation_resolved) }

    it 'returns first page ordered by conversation recency and cursor metadata' do
      result = described_class.new(
        account: account,
        kanban: kanban,
        scope: kanban.kanban_items.includes(:conversation, :kanban_stage),
        params: { stage_id: open_stage.id, limit: 2 }
      ).perform

      expect(result[:items].map(&:id)).to eq([item_3.id, item_2.id])
      expect(result[:meta][:stage_id]).to eq(open_stage.id)
      expect(result[:meta][:has_more]).to be(true)
      expect(result[:meta][:next_cursor]).to be_present
      expect(result[:meta][:limit]).to eq(2)
    end

    it 'supports cursor pagination without duplicating records between pages' do
      first_page = described_class.new(
        account: account,
        kanban: kanban,
        scope: kanban.kanban_items.includes(:conversation, :kanban_stage),
        params: { stage_id: open_stage.id, limit: 2 }
      ).perform

      second_page = described_class.new(
        account: account,
        kanban: kanban,
        scope: kanban.kanban_items.includes(:conversation, :kanban_stage),
        params: {
          stage_id: open_stage.id,
          limit: 2,
          cursor: first_page.dig(:meta, :next_cursor)
        }
      ).perform

      expect(second_page[:items].map(&:id)).to eq([item_1.id])
      expect(second_page[:meta][:has_more]).to be(false)
      expect(second_page[:meta][:next_cursor]).to be_nil
    end

    it 'falls back safely when cursor is invalid' do
      result = described_class.new(
        account: account,
        kanban: kanban,
        scope: kanban.kanban_items.includes(:conversation, :kanban_stage),
        params: { stage_id: open_stage.id, limit: 2, cursor: 'invalid-cursor' }
      ).perform

      expect(result[:items].map(&:id)).to eq([item_3.id, item_2.id])
      expect(result[:meta][:has_more]).to be(true)
    end

    it 'applies exclude_automation_type filter' do
      result = described_class.new(
        account: account,
        kanban: kanban,
        scope: kanban.kanban_items.includes(:conversation, :kanban_stage),
        params: { exclude_automation_type: 'resolved', limit: 10 }
      ).perform

      expect(result[:items].map(&:id)).to match_array([item_1.id, item_2.id, item_3.id])
    end

    it 'clamps limit to the maximum allowed value' do
      result = described_class.new(
        account: account,
        kanban: kanban,
        scope: kanban.kanban_items.includes(:conversation, :kanban_stage),
        params: { stage_id: open_stage.id, limit: 1000 }
      ).perform

      expect(result[:meta][:limit]).to eq(100)
    end
  end
end
