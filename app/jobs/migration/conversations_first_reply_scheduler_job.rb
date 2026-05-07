# Delete migration and spec after 2 consecutive releases.
class Migration::ConversationsFirstReplySchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.blank?

    account.conversations.find_each do |conversation|
      # rubocop:disable Rails/SkipsModelValidations
      # Usa all_messages — backfill historico nao deve filtrar por team_message_isolation.
      outgoing_scope = conversation.all_messages.outgoing.where("(additional_attributes->'campaign_id') is null")
      if outgoing_scope.exists?
        conversation.update_columns(first_reply_created_at: outgoing_scope.first.created_at)
      else
        conversation.update_columns(first_reply_created_at: nil)
      end
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
