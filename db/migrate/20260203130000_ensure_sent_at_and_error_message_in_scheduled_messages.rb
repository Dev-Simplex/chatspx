# frozen_string_literal: true

class EnsureSentAtAndErrorMessageInScheduledMessages < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:scheduled_messages)

    unless column_exists?(:scheduled_messages, :sent_at)
      add_column :scheduled_messages, :sent_at, :datetime
    end

    unless column_exists?(:scheduled_messages, :error_message)
      add_column :scheduled_messages, :error_message, :text
    end
  end

  def down
    return unless table_exists?(:scheduled_messages)

    remove_column :scheduled_messages, :sent_at, :datetime if column_exists?(:scheduled_messages, :sent_at)
    remove_column :scheduled_messages, :error_message, :text if column_exists?(:scheduled_messages, :error_message)
  end
end
