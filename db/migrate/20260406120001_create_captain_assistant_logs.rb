class CreateCaptainAssistantLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :captain_assistant_logs do |t|
      t.references :captain_assistant, null: false, foreign_key: { to_table: :captain_assistants }
      t.references :conversation, null: true, foreign_key: true
      t.bigint :message_id, null: true
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.integer :duration_ms

      t.timestamps
    end

    add_index :captain_assistant_logs, %i[captain_assistant_id event_type], name: 'idx_captain_logs_assistant_event'
    add_index :captain_assistant_logs, :created_at
  end
end
