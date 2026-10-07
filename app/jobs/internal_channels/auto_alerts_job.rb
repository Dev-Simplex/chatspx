# frozen_string_literal: true

# Varre as salas de time com algum aviso automático ligado (ver InternalChannels::AutoAlertsService).
# Com `channel_id`, roda só naquela sala.
class InternalChannels::AutoAlertsJob < ApplicationJob
  queue_as :low

  def perform(channel_id = nil)
    scope = InternalChannel.team.where.not(team_id: nil).where("settings ? 'auto_alerts'")
    scope = scope.where(id: channel_id) if channel_id
    scope.includes(:account).find_each { |channel| InternalChannels::AutoAlertsService.new(channel).perform }
  end
end
