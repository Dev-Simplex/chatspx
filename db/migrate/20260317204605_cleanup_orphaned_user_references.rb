class CleanupOrphanedUserReferences < ActiveRecord::Migration[7.0]
  def up
    # Remove notifications referencing deleted users
    execute <<-SQL.squish
      DELETE FROM notifications
      WHERE user_id NOT IN (SELECT id FROM users)
    SQL

    # Remove conversation participants referencing deleted users
    execute <<-SQL.squish
      DELETE FROM conversation_participants
      WHERE user_id NOT IN (SELECT id FROM users)
    SQL

    # Remove mentions referencing deleted users
    execute <<-SQL.squish
      DELETE FROM mentions
      WHERE user_id NOT IN (SELECT id FROM users)
    SQL

    # Resolve open conversations for blocked contacts
    execute <<-SQL.squish
      UPDATE conversations
      SET status = 1
      FROM contacts
      WHERE conversations.contact_id = contacts.id
        AND contacts.blocked = true
        AND conversations.status = 0
    SQL
  end

  def down
    # Data cleanup is not reversible
  end
end
