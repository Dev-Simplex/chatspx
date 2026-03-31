# Fixes three index issues identified in DB audit:
#
# 1. [MEDIUM] Remove redundant single/dual-column indexes on conversations
#    - index_conversations_on_account_id: covered by 7+ composite indexes
#      leading with account_id (e.g. conv_acid_inbid_stat_asgnid_idx,
#      idx_conv_list_keyset, index_conversations_on_account_id_and_display_id, etc.)
#    - index_conversations_on_status_and_account_id: covered by idx_conv_list_keyset
#      (account_id, status, assignee_id, last_activity_at, id) and similar composites
#
# 2. [LOW] messages.created_at — replace B-tree with BRIN
#    Monotonically increasing column; BRIN is ~100x smaller with minimal query overhead
#
# 3. [LOW] reporting_events.created_at — same as above
#
class RemoveRedundantIndexesAndConvertToBrin < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    # === Fix 1: Remove redundant conversation indexes ===
    remove_index :conversations, name: :index_conversations_on_account_id,
                                 algorithm: :concurrently, if_exists: true

    remove_index :conversations, name: :index_conversations_on_status_and_account_id,
                                 algorithm: :concurrently, if_exists: true

    # === Fix 2: messages.created_at — B-tree → BRIN ===
    remove_index :messages, name: :index_messages_on_created_at,
                            algorithm: :concurrently, if_exists: true

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_messages_on_created_at_brin
      ON messages USING brin (created_at)
      WITH (pages_per_range = 32);
    SQL

    # === Fix 3: reporting_events.created_at — B-tree → BRIN ===
    remove_index :reporting_events, name: :index_reporting_events_on_created_at,
                                    algorithm: :concurrently, if_exists: true

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_reporting_events_on_created_at_brin
      ON reporting_events USING brin (created_at)
      WITH (pages_per_range = 32);
    SQL
  end

  def down
    # === Reverse Fix 3 ===
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_reporting_events_on_created_at_brin;
    SQL

    add_index :reporting_events, :created_at,
              name: :index_reporting_events_on_created_at,
              algorithm: :concurrently, if_not_exists: true

    # === Reverse Fix 2 ===
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_messages_on_created_at_brin;
    SQL

    add_index :messages, :created_at,
              name: :index_messages_on_created_at,
              algorithm: :concurrently, if_not_exists: true

    # === Reverse Fix 1 ===
    add_index :conversations, :account_id,
              name: :index_conversations_on_account_id,
              algorithm: :concurrently, if_not_exists: true

    add_index :conversations, %i[status account_id],
              name: :index_conversations_on_status_and_account_id,
              algorithm: :concurrently, if_not_exists: true
  end
end
