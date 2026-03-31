# frozen_string_literal: true

class Kanban::FunnelLookupService
  pattr_initialize [:account_id!, :inbox_id!, :team_id]

  def perform
    funnels = []

    if team_id.present?
      team_funnel = Funnel.where(team_id: team_id, account_id: account_id)
                          .for_inbox(inbox_id)
                          .first
      funnels << team_funnel if team_funnel
    end

    default_funnel = Funnel.where(account_id: account_id, team_id: nil)
                           .for_inbox(inbox_id)
                           .first
    funnels << default_funnel if default_funnel

    funnels.compact.uniq
  end
end
