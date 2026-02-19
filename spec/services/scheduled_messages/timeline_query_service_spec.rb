# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduledMessages::TimelineQueryService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:scope) { ScheduledMessage.where(conversation_id: conversation.id) }

  def create_scheduled!(minutes_from_now:)
    ScheduledMessage.create!(
      conversation: conversation,
      inbox: conversation.inbox,
      message: 'Scheduled message',
      scheduled_at: minutes_from_now.minutes.from_now,
      status: :pending
    )
  end

  describe '#perform' do
    it 'orders by scheduled_at desc and id desc' do
      older = create_scheduled!(minutes_from_now: 30)
      newer = create_scheduled!(minutes_from_now: 60)

      result = described_class.new(
        scope: scope,
        params: { mode: 'cursor', status: 'all', limit: 10 }
      ).perform

      expect(result[:items].map(&:id)).to eq([newer.id, older.id])
    end

    it 'clamps requested limit to max 100' do
      create_scheduled!(minutes_from_now: 30)

      result = described_class.new(
        scope: scope,
        params: { mode: 'cursor', status: 'all', limit: 999 }
      ).perform

      expect(result[:meta][:limit]).to eq(100)
    end

    it 'does not duplicate records across pages' do
      records = [
        create_scheduled!(minutes_from_now: 30),
        create_scheduled!(minutes_from_now: 60),
        create_scheduled!(minutes_from_now: 90)
      ]
      expected_ids = records.sort_by { |record| [record.scheduled_at, record.id] }.reverse.map(&:id)

      first_page = described_class.new(
        scope: scope,
        params: { mode: 'cursor', status: 'all', limit: 2 }
      ).perform

      second_page = described_class.new(
        scope: scope,
        params: {
          mode: 'cursor',
          status: 'all',
          limit: 2,
          cursor: first_page[:meta][:next_cursor]
        }
      ).perform

      all_ids = first_page[:items].map(&:id) + second_page[:items].map(&:id)
      expect(all_ids).to eq(expected_ids)
      expect(first_page[:items].map(&:id) & second_page[:items].map(&:id)).to eq([])
    end
  end
end
