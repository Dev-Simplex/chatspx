# frozen_string_literal: true

module Conversations
  class ListPreloader
    Result = Struct.new(:unread_counts, :last_messages, :last_non_activity_messages, keyword_init: true)

    def self.call(conversations)
      new(conversations).call
    end

    def initialize(conversations)
      @conversations = conversations.to_a
      @conversation_ids = @conversations.map(&:id)
    end

    def call
      Result.new(
        unread_counts: batch_unread_counts,
        last_messages: batch_last_messages,
        last_non_activity_messages: batch_last_non_activity_messages
      )
    end

    private

    def batch_unread_counts
      return {} if @conversation_ids.empty?

      sql = <<~SQL.squish
        SELECT c.id AS conversation_id, COUNT(m.id)::int AS cnt
        FROM conversations c
        LEFT JOIN messages m ON m.conversation_id = c.id
          AND m.account_id = c.account_id
          AND m.message_type = 0
          AND (c.team_id IS NULL AND m.team_id IS NULL OR c.team_id IS NOT NULL AND m.team_id = c.team_id)
          AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
        WHERE c.id IN (?)
        GROUP BY c.id
      SQL
      rows = Conversation.connection.select_all(
        Conversation.sanitize_sql_array([sql, @conversation_ids])
      )
      rows.to_a.each_with_object({}) do |row, h|
        cnt = row['cnt'].to_i
        h[row['conversation_id'].to_i] = [cnt, 10].min
      end
    end

    def batch_last_messages
      return {} if @conversation_ids.empty?

      sql = <<~SQL.squish
        SELECT DISTINCT ON (m.conversation_id) m.id
        FROM messages m
        INNER JOIN conversations c ON c.id = m.conversation_id
        WHERE m.conversation_id IN (?)
          AND m.account_id = c.account_id
          AND (c.team_id IS NULL AND m.team_id IS NULL OR c.team_id IS NOT NULL AND m.team_id = c.team_id)
        ORDER BY m.conversation_id, m.created_at DESC, m.id DESC
      SQL
      msg_ids = Conversation.connection.select_values(
        Conversation.sanitize_sql_array([sql, @conversation_ids])
      )
      return {} if msg_ids.empty?

      msgs = Message
        .where(id: msg_ids)
        .includes([{ attachments: [{ file_attachment: [:blob] }] }])
        .index_by(&:conversation_id)
      msgs
    end

    def batch_last_non_activity_messages
      return {} if @conversation_ids.empty?

      sql = <<~SQL.squish
        SELECT DISTINCT ON (m.conversation_id) m.id
        FROM messages m
        INNER JOIN conversations c ON c.id = m.conversation_id
        WHERE m.conversation_id IN (?)
          AND m.account_id = c.account_id
          AND m.message_type != 2
          AND (c.team_id IS NULL AND m.team_id IS NULL OR c.team_id IS NOT NULL AND m.team_id = c.team_id)
        ORDER BY m.conversation_id, m.id DESC
      SQL
      msg_ids = Conversation.connection.select_values(
        Conversation.sanitize_sql_array([sql, @conversation_ids])
      )
      return {} if msg_ids.empty?

      Message.where(id: msg_ids).index_by(&:conversation_id)
    end
  end
end
