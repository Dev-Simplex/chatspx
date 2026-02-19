# frozen_string_literal: true

module Kanban
  class BackfillFunnelItemsJob < ApplicationJob
    queue_as :low

    def perform(account_id, funnel_id, moved_by_id = nil)
      account = Account.find_by(id: account_id)
      return if account.blank?

      funnel = account.funnels.find_by(id: funnel_id)
      return if funnel.blank?

      Kanban::FunnelItemsBackfillService.new(
        account: account,
        funnel: funnel,
        moved_by_id: moved_by_id
      ).perform
    end
  end
end
