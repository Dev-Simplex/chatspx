# frozen_string_literal: true

class Kanban::KanbanLookupService
  pattr_initialize [:account_id!, :inbox_id!, :team_id]

  def perform
    kanbans = []

    if team_id.present?
      team_kanban = Kanban.where(team_id: team_id, account_id: account_id)
                          .for_inbox(inbox_id)
                          .first
      kanbans << team_kanban if team_kanban
    end

    default_kanban = Kanban.where(account_id: account_id, team_id: nil)
                           .for_inbox(inbox_id)
                           .first
    kanbans << default_kanban if default_kanban

    kanbans.compact.uniq
  end
end
