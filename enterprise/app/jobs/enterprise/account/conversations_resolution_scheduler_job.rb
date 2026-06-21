module Enterprise::Account::ConversationsResolutionSchedulerJob
  def perform
    super

    resolve_captain_conversations
  end

  private

  def resolve_captain_conversations
    # Dedupe por inbox: com has_many (A5) duas IAs elegíveis na mesma inbox enfileirariam
    # o mesmo job N× — distinct por inbox_id garante 1 job por inbox.
    Inbox.where(id: CaptainInbox.distinct.select(:inbox_id)).find_each(batch_size: 100) do |inbox|
      next if inbox.email?
      next if inbox.account.captain_auto_resolve_disabled?

      Captain::InboxPendingConversationsResolutionJob.perform_later(
        inbox
      )
    end
  end
end
