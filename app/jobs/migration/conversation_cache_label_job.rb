class Migration::ConversationCacheLabelJob < ApplicationJob
  queue_as :async_database_migration

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.blank?

    account.conversations.find_in_batches(batch_size: 100) do |conversation_batch|
      Migration::ConversationBatchCacheLabelJob.perform_later(conversation_batch.map(&:id))
    end
  end
end
