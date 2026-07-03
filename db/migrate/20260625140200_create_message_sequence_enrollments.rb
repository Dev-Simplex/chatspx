# frozen_string_literal: true

# A conversation enrolled into a sequence. Keeps "conversa em primeiro lugar":
# the drip targets a real conversation, never a standalone CRM record. A partial
# unique index allows only one ACTIVE enrollment per (sequence, conversation),
# while still permitting re-enrollment after it completes or is cancelled.
class CreateMessageSequenceEnrollments < ActiveRecord::Migration[7.1]
  def change
    create_table :message_sequence_enrollments do |t|
      t.references :message_sequence, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.integer  :status, null: false, default: 0 # active / completed / cancelled
      t.integer  :current_step_position # position of the next step to send
      t.datetime :next_run_at
      t.bigint   :enrolled_by_id # User (nil = enrolled by an automation)
      t.timestamps
    end
    add_index :message_sequence_enrollments, [:status, :next_run_at]
    add_index :message_sequence_enrollments,
              [:message_sequence_id, :conversation_id],
              unique: true,
              where: 'status = 0',
              name: 'index_active_enrollment_per_sequence_conversation'
  end
end
