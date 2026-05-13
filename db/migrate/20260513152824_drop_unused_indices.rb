# Drop de 5 indices identificados como mortos (0 scans em 7 dias) na auditoria
# PostgreSQL (2026-05-13). Liberam ~126 MB e reduzem overhead em INSERT/UPDATE
# da tabela messages. CONCURRENTLY para nao bloquear escrita.
# Definicoes originais (preservadas no down a partir de db/schema.rb):
#   - idx_messages_account_content_created   : (account_id, content_type, created_at)
#   - idx_messages_team_id                   : (team_id)
#   - index_messages_on_account_id           : (account_id)
#   - index_messages_on_forwarded_from_message_id : (forwarded_from_message_id)
#   - idx_conv_kanban_keyset                 : (account_id, status, last_activity_at DESC, id DESC)
# Ref: docs/stories/sprint-2026-05-13/P1.6-pg-autovacuum-indices-mortos.md (AC2)
class DropUnusedIndices < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute 'SET statement_timeout = 0'

    remove_index :messages, name: 'idx_messages_account_content_created',
                            algorithm: :concurrently, if_exists: true
    remove_index :messages, name: 'idx_messages_team_id',
                            algorithm: :concurrently, if_exists: true
    remove_index :messages, name: 'index_messages_on_account_id',
                            algorithm: :concurrently, if_exists: true
    remove_index :messages, name: 'index_messages_on_forwarded_from_message_id',
                            algorithm: :concurrently, if_exists: true
    remove_index :conversations, name: 'idx_conv_kanban_keyset',
                                 algorithm: :concurrently, if_exists: true
  end

  def down
    execute 'SET statement_timeout = 0'

    add_index :messages, %i[account_id content_type created_at],
              name: 'idx_messages_account_content_created',
              algorithm: :concurrently, if_not_exists: true

    add_index :messages, :team_id,
              name: 'idx_messages_team_id',
              algorithm: :concurrently, if_not_exists: true

    add_index :messages, :account_id,
              name: 'index_messages_on_account_id',
              algorithm: :concurrently, if_not_exists: true

    add_index :messages, :forwarded_from_message_id,
              name: 'index_messages_on_forwarded_from_message_id',
              algorithm: :concurrently, if_not_exists: true

    add_index :conversations, %i[account_id status last_activity_at id],
              name: 'idx_conv_kanban_keyset',
              order: { last_activity_at: :desc, id: :desc },
              algorithm: :concurrently, if_not_exists: true
  end
end
