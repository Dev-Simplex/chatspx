class CreateMessageReactions < ActiveRecord::Migration[7.1]
  def change
    create_table :message_reactions do |t|
      t.references :message, null: false, foreign_key: true, index: true
      t.references :account, null: false, foreign_key: true, index: true
      t.string :user_type, null: false
      t.bigint :user_id, null: false
      t.string :emoji, null: false, limit: 10

      t.timestamps
    end

    add_index :message_reactions, [:message_id, :user_type, :user_id], unique: true, name: 'index_message_reactions_unique'
    add_index :message_reactions, [:user_type, :user_id]
  end
end



