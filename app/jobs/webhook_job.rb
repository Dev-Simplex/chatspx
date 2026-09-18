class WebhookJob < ApplicationJob
  queue_as :medium
  # Sem o bloco, esgotadas as 5 tentativas o erro subiria para o Sidekiq e reenviaria por dias.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    url, payload, webhook_type = job.arguments
    Webhooks::Trigger.new(url, payload, webhook_type || :account_webhook).handle_failure(error)
  end
  discard_on ActiveJob::DeserializationError
  #  There are 3 types of webhooks, account, inbox and agent_bot
  def perform(url, payload, webhook_type = :account_webhook, secret: nil, delivery_id: nil)
    Webhooks::Trigger.execute(url, payload, webhook_type, secret: secret, delivery_id: delivery_id)
  end
end
