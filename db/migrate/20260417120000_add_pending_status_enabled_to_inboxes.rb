class AddPendingStatusEnabledToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :pending_status_enabled, :boolean, default: false, null: false
  end
end
