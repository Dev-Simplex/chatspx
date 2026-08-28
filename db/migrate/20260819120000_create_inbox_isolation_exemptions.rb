class CreateInboxIsolationExemptions < ActiveRecord::Migration[7.1]
  # Aditiva e INERTE: enquanto nenhuma linha existir, os dois isolamentos se comportam
  # exatamente como hoje. É por isso que a tabela guarda EXCEÇÕES (quem NÃO participa)
  # e não participantes — guardar participantes faria toda caixa já existente entrar no
  # deploy com lista vazia e o isolamento simplesmente deixaria de valer, em silêncio.
  #
  # Espelha `team_supervisors`, que já é o padrão da casa para "quem escapa da regra".
  def up
    create_table :inbox_isolation_exemptions, if_not_exists: true do |t|
      t.bigint :inbox_id, null: false
      t.bigint :user_id, null: false
      # 'agent_message' | 'team_message' — os dois isolamentos são independentes,
      # por isso o tipo entra na chave e não numa tabela por regra.
      t.string :isolation_type, null: false
      t.timestamps
    end

    # (inbox, user, tipo) único: isentar duas vezes a mesma pessoa da mesma regra é ruído.
    add_index :inbox_isolation_exemptions, %i[inbox_id user_id isolation_type],
              unique: true, name: 'index_inbox_isolation_exemptions_on_inbox_user_type', if_not_exists: true
    # a pergunta quente na limpeza é "quais isenções este usuário tem?" (saída da conta)
    add_index :inbox_isolation_exemptions, :user_id, if_not_exists: true

    add_foreign_key :inbox_isolation_exemptions, :inboxes, on_delete: :cascade unless foreign_key_exists?(:inbox_isolation_exemptions, :inboxes)
    return if foreign_key_exists?(:inbox_isolation_exemptions, :users)

    add_foreign_key :inbox_isolation_exemptions, :users, on_delete: :cascade
  end

  def down
    drop_table :inbox_isolation_exemptions
  end
end
