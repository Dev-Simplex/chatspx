class AddWahaSessionNameToInboxes < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:inboxes, :waha_session_name)

    add_column :inboxes, :waha_session_name, :string
  end
end
