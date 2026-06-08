# frozen_string_literal: true

# KANBAN-P2-02: recalcula aging_days de todos os KanbanItems.
# Disparado por scheduler (configurar em sidekiq-cron ao ativar em prod).
class Kanban::AgingCalculationJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id = nil)
    scope = account_id ? KanbanItem.joins(:kanban).where(kanbans: { account_id: account_id }) : KanbanItem.all
    KanbanItems::AgingService.call(scope: scope)
  end
end
