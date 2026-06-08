# frozen_string_literal: true

# KANBAN-P2-06: marca card como won.
# - persiste won_reason
# - opcionalmente seta metadata.value_cents
# - marca conversa como resolved (se ainda nao estiver)
class KanbanItems::MarkWonService
  attr_reader :item, :reason, :value_cents, :source, :detail, :user

  def initialize(item:, user: nil, reason: nil, value_cents: nil, source: nil, detail: nil) # rubocop:disable Metrics/ParameterLists
    @item = item
    @user = user
    @reason = reason
    @value_cents = value_cents
    @source = source
    @detail = detail
  end

  def perform # rubocop:disable Metrics/AbcSize
    KanbanItem.transaction do
      meta = item.metadata || {}
      meta['value_cents'] = value_cents.to_i if value_cents.present?
      meta['source']      = source if source.present?

      item.update!(
        won_reason: [reason, detail].compact.reject(&:blank?).join(' | '),
        metadata: meta
      )

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
