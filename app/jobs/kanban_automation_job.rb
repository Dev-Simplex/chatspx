# frozen_string_literal: true

# KANBAN-P3-05: roda automations enfileiradas pelo DispatcherService.
class KanbanAutomationJob < ApplicationJob
  queue_as :default

  def perform(trigger, item_id, previous_stage_id = nil)
    item = KanbanItem.find_by(id: item_id)
    return unless item

    KanbanAutomations::DispatcherService.new(
      trigger: trigger.to_s,
      item: item,
      previous_stage_id: previous_stage_id
    ).perform
  rescue StandardError => e
    Rails.logger.tagged('kanban-automations').error("[Job item=#{item_id} trigger=#{trigger}] #{e.message}")
    raise unless Rails.env.production?
  end
end
