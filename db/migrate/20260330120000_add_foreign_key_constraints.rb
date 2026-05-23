class AddForeignKeyConstraints < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # Adds foreign key constraints to core tables that were created before FK conventions were adopted.
  # Uses the non-blocking pattern: clean orphans -> add unvalidated FK -> validate separately.

  FOREIGN_KEYS = [
    # ALL tables referencing conversations — must be processed FIRST so their FKs
    # use cascade before we attempt to clean orphaned conversations below
    { from: :conversation_assignment_histories, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :applied_slas, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :sla_events, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :funnel_items, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :scheduled_messages, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :nps_responses, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: true },
    { from: :csat_survey_responses, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: true },
    { from: :reporting_events, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: true },
    { from: :conversation_participants, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :mentions, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :messages, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },

    # HIGH Priority — core tables (conversations can now be safely cleaned)
    { from: :conversations, to: :accounts,  column: :account_id,  on_delete: :cascade,  nullable: false },
    { from: :conversations, to: :inboxes,   column: :inbox_id,    on_delete: :cascade,  nullable: false },
    { from: :conversations, to: :contacts,  column: :contact_id,  on_delete: :restrict, nullable: true },
    { from: :conversations, to: :users,     column: :assignee_id, on_delete: :nullify,  nullable: true },
    { from: :conversations, to: :teams,     column: :team_id,     on_delete: :nullify,  nullable: true },
    { from: :messages,      to: :accounts,  column: :account_id,  on_delete: :cascade,  nullable: false },
    { from: :messages,      to: :inboxes,   column: :inbox_id,    on_delete: :cascade,  nullable: false },

    # MEDIUM Priority
    { from: :notifications, to: :accounts, column: :account_id, on_delete: :cascade, nullable: false },
    { from: :notifications, to: :users,    column: :user_id,    on_delete: :cascade, nullable: false },
    { from: :contact_inboxes, to: :contacts, column: :contact_id, on_delete: :cascade, nullable: true },
    { from: :contact_inboxes, to: :inboxes,  column: :inbox_id,   on_delete: :cascade, nullable: true },
    { from: :conversation_participants, to: :accounts, column: :account_id, on_delete: :cascade, nullable: false }
  ].freeze

  def up
    FOREIGN_KEYS.each do |fk|
      add_fk(fk)
    end
  end

  def down
    FOREIGN_KEYS.reverse_each do |fk|
      remove_fk(fk)
    end
  end

  private

  def add_fk(fk)
    from_table  = fk[:from]
    to_table    = fk[:to]
    column      = fk[:column]
    on_delete   = fk[:on_delete]
    nullable    = fk[:nullable]

    # If FK already exists, drop it first so we can re-add with the correct on_delete action
    remove_foreign_key from_table, to_table, column: column if foreign_key_exists?(from_table, to_table, column: column)

    # Step 1: Clean orphaned rows
    if nullable
      safety_execute(<<~SQL.squish)
        DELETE FROM #{from_table}
        WHERE #{column} IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #{to_table} WHERE #{to_table}.id = #{from_table}.#{column})
      SQL
    else
      safety_execute(<<~SQL.squish)
        DELETE FROM #{from_table}
        WHERE NOT EXISTS (SELECT 1 FROM #{to_table} WHERE #{to_table}.id = #{from_table}.#{column})
      SQL
    end

    # Step 2: Add FK without validation (instant, no lock)
    add_foreign_key from_table, to_table, column: column, on_delete: on_delete, validate: false

    # Step 3: Validate (scans table but does not hold exclusive lock)
    validate_foreign_key from_table, to_table, column: column
  end

  def remove_fk(fk)
    from_table = fk[:from]
    to_table   = fk[:to]
    column     = fk[:column]

    return unless foreign_key_exists?(from_table, to_table, column: column)

    remove_foreign_key from_table, to_table, column: column
  end

  def safety_execute(sql)
    say_with_time(sql.truncate(120)) do
      execute(sql)
    end
  end
end
