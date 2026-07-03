# frozen_string_literal: true

# A single step of a message sequence: the visible text (content) and the delay
# (in minutes) to wait BEFORE sending it, measured from the previous step's send
# (or from enrollment for the first step). template_params carries an optional
# WhatsApp HSM payload for sending outside the 24h window (Cloud API only).
class CreateMessageSequenceSteps < ActiveRecord::Migration[7.1]
  def change
    create_table :message_sequence_steps do |t|
      t.references :message_sequence, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :delay_minutes, null: false, default: 0
      t.text    :content
      t.jsonb   :template_params # { name:, language:, processed_params: { body: {...} } }
      t.timestamps
    end
    add_index :message_sequence_steps, [:message_sequence_id, :position]
  end
end
