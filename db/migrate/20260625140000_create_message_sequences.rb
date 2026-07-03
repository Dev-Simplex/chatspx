# frozen_string_literal: true

# Follow-up drip (Módulo A) — a named, user-configurable sequence of messages
# fired at intervals after a conversation is enrolled. Generalizes the hardcoded
# Spx::Tozi::ReactivationCadenceService. New table → additive, reversible, inert
# until a manager creates a sequence and someone enrolls a conversation.
class CreateMessageSequences < ActiveRecord::Migration[7.1]
  def change
    create_table :message_sequences do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :name, null: false
      t.boolean :active, null: false, default: true
      t.jsonb   :exit_conditions, null: false, default: {} # { on_customer_reply: true, on_status: 'resolved' }
      t.bigint  :created_by_id # User who authored it (no FK: users may be deleted)
      t.timestamps
    end
    add_index :message_sequences, [:account_id, :active]
  end
end
