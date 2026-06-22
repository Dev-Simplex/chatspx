class CreateMessageReactions < ActiveRecord::Migration[7.1]
  # A feature de reações (PR B1) entrou no schema.rb sem migration em db/migrate.
  # Em VMs criadas via db:migrate (não schema:load) a tabela nunca era criada e o
  # eager-load :reactions do MessageFinder dava PG::UndefinedTable -> 500 no endpoint
  # de mensagens. Idempotente: pula onde já existe (criada manualmente no incidente).
  def change
    return if table_exists?(:message_reactions)

    create_table :message_reactions do |t|
      t.bigint :message_id, null: false
      t.bigint :account_id, null: false
      t.string :user_type, null: false
      t.bigint :user_id, null: false
      t.string :emoji, limit: 10, null: false
      t.timestamps
    end
    add_index :message_reactions, :account_id, name: 'index_message_reactions_on_account_id'
    add_index :message_reactions, %i[message_id user_type user_id], unique: true, name: 'index_message_reactions_unique'
    add_index :message_reactions, :message_id, name: 'index_message_reactions_on_message_id'
    add_index :message_reactions, %i[user_type user_id], name: 'index_message_reactions_on_user_type_and_user_id'
  end
end
