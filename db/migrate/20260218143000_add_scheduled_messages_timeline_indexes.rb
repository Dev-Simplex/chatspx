# frozen_string_literal: true

class AddScheduledMessagesTimelineIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :scheduled_messages,
              [:status, :scheduled_at, :id],
              order: { scheduled_at: :desc, id: :desc },
              name: 'idx_scheduled_messages_status_timeline',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :scheduled_messages,
              [:conversation_id, :scheduled_at, :id],
              order: { scheduled_at: :desc, id: :desc },
              name: 'idx_scheduled_messages_conversation_timeline',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
