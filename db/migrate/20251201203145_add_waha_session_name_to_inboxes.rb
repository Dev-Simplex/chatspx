class AddWahaSessionNameToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :waha_session_name, :string
    add_index :inboxes, :waha_session_name
  end
end


