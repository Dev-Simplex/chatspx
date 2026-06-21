# Vigia de órfãs (Fase C / C10 — D-12) + vigia da fila por time (Fase F3 — F-5):
# fan-out por conta com o modo "Atribuição obrigatória" (reply_assignment_gate) ligado.
# Precedente: Account::ConversationsResolutionSchedulerJob.
class Account::OrphanConversationsWatchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.with_reply_assignment_gate.find_each(batch_size: 100) do |account|
      Conversations::OrphanRetriageJob.perform_later(account)
      Conversations::QueueEscalationJob.perform_later(account)
    end
  end
end
