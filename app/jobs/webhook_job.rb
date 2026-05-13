class WebhookJob < ApplicationJob
  queue_as :medium
  # Aggressive retry cap (3 total attempts) to avoid retry-storms against dead webhook hosts (e.g. n8n down).
  # See story P1.7 / audit 2026-05-13 §3.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  #  There are 3 types of webhooks, account, inbox and agent_bot
  def perform(url, payload, webhook_type = :account_webhook, secret: nil, delivery_id: nil)
    Webhooks::Trigger.execute(url, payload, webhook_type, secret: secret, delivery_id: delivery_id)
  end
end
