# Batch horário do eval. Varre as contas com o gate ligado e enfileira a avaliação
# das conversas tocadas por IA (inbox com CaptainInbox) com atividade recente.
# NO-OP em contas sem custom_attributes['eval_enabled']. O ConversationEvalJob
# decide se cada conversa realmente precisa reavaliar (idempotência).
class Captain::ConversationEvalSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  ELIGIBILITY_WINDOW = 25.hours
  MAX_PER_ACCOUNT = 200

  def perform
    Account.find_each(batch_size: 100) do |account|
      next unless Captain::ConversationEval.enabled_for?(account)

      enqueue_for_account(account)
    end
  end

  private

  def enqueue_for_account(account)
    captain_inbox_ids = CaptainInbox.where(inbox_id: account.inboxes.select(:id)).distinct.pluck(:inbox_id)
    return if captain_inbox_ids.empty?

    account.conversations
           .where(inbox_id: captain_inbox_ids)
           .where('last_activity_at >= ?', ELIGIBILITY_WINDOW.ago)
           .order(last_activity_at: :desc)
           .limit(MAX_PER_ACCOUNT)
           .each { |conversation| Captain::ConversationEvalJob.perform_later(conversation) }
  end
end
