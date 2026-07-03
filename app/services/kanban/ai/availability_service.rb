# frozen_string_literal: true

# Kanban v2 (Fase 7) — is AI usable for this account? We REUSE Chatwoot's
# existing Captain task services (summarize / reply / sentiment / labels) rather
# than building parallel ones; this just answers whether the UI should offer
# those actions. Degrades to false (never raises) when AI isn't configured.
class Kanban::Ai::AvailabilityService
  def initialize(account:)
    @account = account
  end

  def available?
    return false unless @account&.feature_enabled?('captain_tasks')

    Captain::OpenaiHookService.new(account: @account).configured?
  rescue StandardError => e
    Rails.logger.warn("Kanban::Ai availability check failed: #{e.message}")
    false
  end
end
