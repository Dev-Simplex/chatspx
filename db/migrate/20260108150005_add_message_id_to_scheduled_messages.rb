class AddMessageIdToScheduledMessages < ActiveRecord::Migration[6.1]
  def change
    add_reference :scheduled_messages, :message, foreign_key: true, null: true, index: true
  end
end

