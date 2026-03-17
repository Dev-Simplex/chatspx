class DeduplicateConversationsAndAddConstraint < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    # Phase 4: Deduplicate existing conversations
    # For inboxes with lock_to_single_conversation, resolve duplicate non-resolved conversations
    # keeping the oldest one open
    execute <<-SQL.squish
      WITH duplicates AS (
        SELECT c.id, c.contact_id, c.inbox_id, c.created_at,
               ROW_NUMBER() OVER (
                 PARTITION BY c.inbox_id, c.contact_id
                 ORDER BY c.created_at ASC
               ) AS rn
        FROM conversations c
        INNER JOIN inboxes i ON i.id = c.inbox_id
        WHERE i.lock_to_single_conversation = true
          AND c.status != 1
      )
      UPDATE conversations
      SET status = 1
      WHERE id IN (
        SELECT id FROM duplicates WHERE rn > 1
      )
    SQL

    # Phase 3: Add partial unique index to prevent future duplicates
    # Only applies to non-resolved conversations (status != 1) in lock_to_single_conversation inboxes
    add_index :conversations, %i[inbox_id contact_id],
              unique: true,
              where: 'status != 1 AND inbox_id IN (SELECT id FROM inboxes WHERE lock_to_single_conversation = true)',
              name: 'idx_unique_active_conv_per_contact_inbox',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :conversations, name: 'idx_unique_active_conv_per_contact_inbox', if_exists: true
  end
end
