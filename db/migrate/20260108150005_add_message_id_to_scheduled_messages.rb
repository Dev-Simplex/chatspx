# frozen_string_literal: true

class AddMessageIdToScheduledMessages < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:scheduled_messages)
    return if column_exists?(:scheduled_messages, :message_id)

    add_reference :scheduled_messages, :message, foreign_key: true, null: true, index: true
  end

  def down
    return unless table_exists?(:scheduled_messages)
    remove_reference :scheduled_messages, :message, foreign_key: true if column_exists?(:scheduled_messages, :message_id)
  end
end
