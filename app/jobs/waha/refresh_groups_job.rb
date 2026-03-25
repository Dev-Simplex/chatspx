# frozen_string_literal: true

class Waha::RefreshGroupsJob < ApplicationJob
  queue_as :low

  # Refresh all WAHA groups to populate LID→PN mappings
  # WAHA populates LID mappings when groups are fetched
  def perform
    session_names = Inbox.where.not(waha_session_name: [nil, '']).distinct.pluck(:waha_session_name)
    return if session_names.blank?

    service = Waha::ApiService.new
    session_names.each do |session_name|
      service.get_groups(session_name)
      Rails.logger.info("[RefreshGroupsJob] Refreshed groups for session: #{session_name}")
    rescue Waha::ApiService::Error => e
      Rails.logger.warn("[RefreshGroupsJob] Failed to refresh groups for #{session_name}: #{e.message}")
    end
  end
end
