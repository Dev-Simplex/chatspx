# frozen_string_literal: true

# A message inside an internal channel. Attachments ride on Active Storage.
class CreateInternalMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_messages do |t|
      t.references :internal_channel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false
      t.timestamps
    end
    add_index :internal_messages, [:internal_channel_id, :created_at]
  end
end
