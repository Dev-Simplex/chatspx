class AddForwardedToMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :messages, :forwarded, :boolean, default: false, null: false
    add_column :messages, :forwarded_from_message_id, :bigint
    add_column :messages, :starred, :boolean, default: false, null: false

    add_index :messages, :forwarded_from_message_id
    add_index :messages, :starred
  end
end

