# Corrige regressao da 20260330120000: a FK conversations.contact_id ficou ON DELETE RESTRICT,
# o que quebra a exclusao de QUALQUER contato com conversa (Chatwoot usa dependent: :destroy_async,
# que apaga o contato antes das conversas -> PG::ForeignKeyViolation -> 500).
# Alinha com as demais FKs (messages, contact_inboxes ja sao CASCADE): excluir contato volta a
# cascatear conversas+mensagens, comportamento padrao do Chatwoot.
# Padrao nao-bloqueante: re-add NOT VALID -> validate separado (sem lock longo / sem downtime).
class ChangeConversationsContactFkToCascade < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    change_fk(:cascade)
  end

  def down
    change_fk(:restrict)
  end

  private

  def change_fk(on_delete)
    return unless table_exists?(:conversations) && table_exists?(:contacts)

    remove_foreign_key :conversations, :contacts, column: :contact_id if foreign_key_exists?(:conversations, :contacts, column: :contact_id)
    add_foreign_key :conversations, :contacts, column: :contact_id, on_delete: on_delete, validate: false

    # validate scaneia a tabela; afrouxa o timeout so nesta sessao de migration (online)
    connection.execute("SET statement_timeout = '60min'")
    validate_foreign_key :conversations, :contacts, column: :contact_id
  end
end
