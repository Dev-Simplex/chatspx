class Notification::PushNotificationJob < ApplicationJob
  queue_as :default

  # 5xx de quem entrega o push e falha passageira: tenta de novo, com espaco. Esgotadas as tentativas, reporta —
  # sem o bloco o ActiveJob devolveria o erro ao Sidekiq, que reenviaria por dias (a licao do T13).
  retry_on Notification::PushNotificationService::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    ChatwootExceptionTracker.new(error, account: Notification.find_by(id: job.arguments.first)&.account).capture_exception
  end

  # `subscription_id` so vem na retentativa de uma inscricao (ver PushNotificationService#deliver).
  def perform(notification_id, subscription_id = nil)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    Notification::PushNotificationService.new(notification: notification, subscription_id: subscription_id).perform
  end
end
