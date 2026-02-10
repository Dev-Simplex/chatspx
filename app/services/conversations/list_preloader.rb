class Conversations::ListPreloader
  def initialize(conversations, account_id:)
    @conversations = conversations
    @account_id = account_id
  end

  def perform
    conversation_ids = extract_conversation_ids
    return empty_payload if conversation_ids.empty?

    {
      last_messages_by_conversation_id: fetch_last_messages(conversation_ids),
      last_non_activity_messages_by_conversation_id: fetch_last_non_activity_messages(conversation_ids),
      unread_counts_by_conversation_id: fetch_unread_counts(conversation_ids)
    }
  end

  private

  def extract_conversation_ids
    ids = if @conversations.respond_to?(:pluck)
            @conversations.pluck(:id)
          else
            Array(@conversations).map(&:id)
          end

    ids.compact.uniq
  end

  def empty_payload
    {
      last_messages_by_conversation_id: {},
      last_non_activity_messages_by_conversation_id: {},
      unread_counts_by_conversation_id: {}
    }
  end

  def fetch_last_messages(conversation_ids)
    messages = Message.where(account_id: @account_id, conversation_id: conversation_ids)
                      .includes(attachments: { file_attachment: [:blob] })
                      .select('DISTINCT ON (conversation_id) messages.*')
                      .reorder('conversation_id, id DESC')

    messages.index_by(&:conversation_id)
  end

  def fetch_last_non_activity_messages(conversation_ids)
    messages = Message.where(account_id: @account_id, conversation_id: conversation_ids)
                      .where.not(message_type: Message.message_types[:activity])
                      .includes(attachments: { file_attachment: [:blob] })
                      .select('DISTINCT ON (conversation_id) messages.*')
                      .reorder('conversation_id, id DESC')

    messages.index_by(&:conversation_id)
  end

  def fetch_unread_counts(conversation_ids)
    conversation_table = Conversation.table_name
    rows = Message.where(account_id: @account_id,
                         conversation_id: conversation_ids,
                         message_type: Message.message_types[:incoming])
                  .joins("INNER JOIN #{conversation_table} ON #{conversation_table}.id = messages.conversation_id")
                  .where("#{conversation_table}.agent_last_seen_at IS NULL OR messages.created_at > #{conversation_table}.agent_last_seen_at")
                  .group('messages.conversation_id')
                  .pluck('messages.conversation_id', 'LEAST(COUNT(*), 10)')

    rows.to_h
  end
end
