# frozen_string_literal: true

class Kanban::BackfillKanbanItemsJob < ApplicationJob
  queue_as :low

  def perform(account_id, kanban_id, moved_by_id = nil)
    account = Account.find_by(id: account_id)
    return if account.blank?

    kanban = account.kanbans.find_by(id: kanban_id)
    return if kanban.blank?

    Kanban::KanbanItemsBackfillService.new(
      account: account,
      kanban: kanban,
      moved_by_id: moved_by_id
    ).perform
  end
end
