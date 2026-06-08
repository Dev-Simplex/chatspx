# frozen_string_literal: true

# KANBAN-P3-02: enfileira classificação Captain pra um KanbanItem novo.
# Roda em queue :low (não bloqueia critical path). Idempotente.
class KanbanCaptain::TriageJob < ApplicationJob
  queue_as :low

  def perform(item_id)
    item = KanbanItem.find_by(id: item_id)
    return unless item

    KanbanCaptain::TriageService.call(item: item)
  rescue StandardError => e
    Rails.logger.tagged('kanban-captain').error("[TriageJob##{item_id}] #{e.message}")
    raise unless Rails.env.production?
  end
end
