# frozen_string_literal: true

class AddPerformanceIndexesRound2 < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    # messages: prevent_message_flooding executa WHERE (conversation_id, created_at) a cada mensagem criada
    # o índice existente (conversation_id, account_id, message_type, created_at) não é ideal para essa query
    add_index :messages,
              %i[conversation_id created_at],
              name: 'idx_messages_conversation_id_created_at',
              algorithm: :concurrently,
              if_not_exists: true

    # conversations: sidebar conta conversas por assignee + status separadamente (3 queries)
    add_index :conversations,
              %i[assignee_id status],
              name: 'idx_conversations_assignee_id_status',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
