# frozen_string_literal: true

# KANBAN-P2-06: marca card como lost (motivo obrigatório).
class KanbanItems::MarkLostService
  attr_reader :item, :reason, :tags, :user

  def initialize(item:, reason:, user: nil, tags: nil)
    @item = item
    @user = user
    @reason = reason
    @tags = tags
  end

  def perform # rubocop:disable Metrics/AbcSize
    raise ArgumentError, 'reason required' if reason.to_s.strip.blank?

    KanbanItem.transaction do
      meta = item.metadata || {}
      meta['lost_tags'] = Array(tags).reject(&:blank?) if tags.present?

      item.update!(loss_reason: reason.to_s.strip, metadata: meta)

      conversation = item.conversation
      conversation.update!(status: :resolved) if conversation.present? && conversation.status != 'resolved'
    end
    Kanbans::MetricsService.invalidate(item.kanban_id)
    item
  end

  def self.call(**)
    new(**).perform
  end
end
