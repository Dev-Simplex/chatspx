# frozen_string_literal: true

# Membership of a user in an internal channel. last_read_at powers the unread badge.
class CreateInternalChannelMembers < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_channel_members do |t|
      t.references :internal_channel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :last_read_at
      t.timestamps
    end
    add_index :internal_channel_members, [:internal_channel_id, :user_id], unique: true
  end
end
