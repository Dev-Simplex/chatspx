# frozen_string_literal: true

class AddScheduledByToScheduledMessages < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:scheduled_messages)
    return if column_exists?(:scheduled_messages, :scheduled_by_id)

    add_reference :scheduled_messages, :scheduled_by, foreign_key: { to_table: :users }, index: true, null: true
  end

  def down
    return unless table_exists?(:scheduled_messages)
    remove_reference :scheduled_messages, :scheduled_by, foreign_key: { to_table: :users } if column_exists?(:scheduled_messages, :scheduled_by_id)
  end
end
