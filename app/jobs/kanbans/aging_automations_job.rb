# frozen_string_literal: true

# KANBAN-P3-05: dispara automations do tipo `item_aging_threshold` para
# todos os cards que cruzaram o limite definido.
class Kanbans::AgingAutomationsJob < ApplicationJob
  queue_as :default

  def perform
    KanbanAutomation.enabled.by_trigger('item_aging_threshold').find_each do |automation|
      days = automation.conditions.is_a?(Hash) ? automation.conditions['days'].to_i : 0
      next if days <= 0

      scope = KanbanItem.where(kanban_id: automation.kanban_id).where('aging_days >= ?', days)
      scope = scope.where(kanban_stage_id: automation.kanban_stage_id) if automation.kanban_stage_id.present?
      scope.find_each do |item|
        KanbanAutomations::DispatcherService.fire(trigger: 'item_aging_threshold', item: item)
      end
    end
  end
end
