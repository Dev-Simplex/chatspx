# frozen_string_literal: true

class RemoveWahaSessionNameFromScheduledMessages < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:scheduled_messages)
    return unless column_exists?(:scheduled_messages, :waha_session_name)

    remove_column :scheduled_messages, :waha_session_name, :string
  end

  def down
    return unless table_exists?(:scheduled_messages)
    return if column_exists?(:scheduled_messages, :waha_session_name)

    add_column :scheduled_messages, :waha_session_name, :string
  end
end
