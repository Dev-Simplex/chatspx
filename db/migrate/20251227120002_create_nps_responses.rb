class CreateNpsResponses < ActiveRecord::Migration[7.0]
  def change
    create_table :nps_responses do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :contact_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :assigned_agent_id
      t.integer :status, default: 0, null: false
      t.integer :score
      t.text :comment
      t.datetime :sent_at
      t.datetime :answered_at
      t.string :dismiss_reason
      t.string :blocked_by_label
      t.integer :blocked_scope
      t.jsonb :metadata
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index :account_id
      t.index :conversation_id, unique: true
      t.index :contact_id
      t.index :inbox_id
      t.index :assigned_agent_id
      t.index [:account_id, :sent_at]
      t.index [:account_id, :answered_at]
      t.index [:contact_id, :answered_at]
      t.index :status
    end
  end
end
