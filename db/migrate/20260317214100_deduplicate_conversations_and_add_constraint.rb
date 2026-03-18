class DeduplicateConversationsAndAddConstraint < ActiveRecord::Migration[7.0]
  def up
    # Deduplicate existing conversations for lock_to_single_conversation inboxes
    # For each (inbox, contact) pair, keep the oldest non-resolved conversation and resolve the rest
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
  end

  def down
    # Data cleanup is not reversible
  end
end
