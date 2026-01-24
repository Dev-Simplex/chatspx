class RemoveWahaSessionNameFromScheduledMessages < ActiveRecord::Migration[6.1]
  def change
    remove_column :scheduled_messages, :waha_session_name, :string
  end
end

