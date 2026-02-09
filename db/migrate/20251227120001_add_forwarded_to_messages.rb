class AddForwardedToMessages < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:messages, :forwarded)
      add_column :messages, :forwarded, :boolean, default: false, null: false
    end

    unless column_exists?(:messages, :forwarded_from_message_id)
      add_column :messages, :forwarded_from_message_id, :bigint
    end

    unless column_exists?(:messages, :starred)
      add_column :messages, :starred, :boolean, default: false, null: false
    end

    add_index :messages, :forwarded_from_message_id unless index_exists?(:messages, :forwarded_from_message_id)
    add_index :messages, :starred unless index_exists?(:messages, :starred)
  end
end
