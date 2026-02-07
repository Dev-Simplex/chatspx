# frozen_string_literal: true

class CreateScheduledMessages < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:scheduled_messages)

    create_table :scheduled_messages do |t|
      t.references :conversation, null: false, foreign_key: true, index: true
      t.references :inbox, null: false, foreign_key: true, index: true
      t.text :message, null: false
      t.datetime :scheduled_at, null: false
      t.integer :status, default: 0
      t.string :waha_session_name
      t.datetime :sent_at
      t.text :error_message

      t.timestamps
    end

    add_index :scheduled_messages, :scheduled_at
    add_index :scheduled_messages, :status
  end

  def down
    drop_table :scheduled_messages, if_exists: true
  end
end
