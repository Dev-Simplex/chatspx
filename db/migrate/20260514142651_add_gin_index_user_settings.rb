class AddGinIndexUserSettings < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :conversations,
              "((additional_attributes->'user_settings'))",
              using: :gin,
              name: 'index_conversations_on_user_settings_gin',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :conversations,
                 name: 'index_conversations_on_user_settings_gin',
                 if_exists: true
  end
end
