# Adiciona messages.agent_id (espelho de messages.team_id) para o isolamento de
# mensagens POR AGENTE. Carimbado no envio (Message#set_agent_id_from_sender).
# Padrao nao-bloqueante p/ tabela grande: coluna nullable (instantanea no PG) +
# indice CONCURRENTLY + FK validate:false depois validada (mesmo padrao de
# 20260330120000_add_foreign_key_constraints). FK com ON DELETE NULLIFY: ao
# deletar um agente, suas mensagens viram publicas (agent_id NULL) — NUNCA :restrict.
class AddAgentIdToMessages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :messages, :agent_id, :bigint, null: true unless column_exists?(:messages, :agent_id)
    add_index :messages, :agent_id, algorithm: :concurrently unless index_exists?(:messages, :agent_id)

    unless foreign_key_exists?(:messages, :users, column: :agent_id)
      add_foreign_key :messages, :users, column: :agent_id, on_delete: :nullify, validate: false
    end
    validate_foreign_key :messages, :users, column: :agent_id
  end

  def down
    remove_foreign_key :messages, :users, column: :agent_id if foreign_key_exists?(:messages, :users, column: :agent_id)
    remove_index :messages, :agent_id, algorithm: :concurrently if index_exists?(:messages, :agent_id)
    remove_column :messages, :agent_id if column_exists?(:messages, :agent_id)
  end
end
