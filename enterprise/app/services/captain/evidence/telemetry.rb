module Captain::Evidence::Telemetry
  module_function

  # Independent of the ledger database: its outage must not look like zero violations.
  def emit(payload)
    event = { event: 'captain.fact_guard.shadow', mode: 'shadow', at: Time.current.iso8601(6), **payload }
    Rails.logger.info(event.to_json)
    ActiveSupport::Notifications.instrument('shadow.fact_guard.captain', event)
  rescue StandardError
    nil # telemetry subscribers cannot change customer-visible behavior
  end
end
