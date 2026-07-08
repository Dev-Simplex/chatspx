# frozen_string_literal: true

# P2 do plano task/kanban-db-restructure.md — integridade referencial de assignee_id.
#
# funnel_items.assignee_id (cartões de tarefa) tinha índice mas NENHUMA foreign key:
# ao deletar um usuário, o item ficava com assignee_id órfão, sem nullify no banco.
# Pré-check no staging: 0 órfãos. Aditiva e reversível.
#
# Padrão de baixo lock: adiciona a FK como NOT VALID (não varre a tabela / lock curto)
# e valida em passo separado — seguro quando isto alcançar bancos maiores na frota.
class AddForeignKeyToFunnelItemsAssignee < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    return if foreign_key_exists?(:funnel_items, :users, column: :assignee_id)

    add_foreign_key :funnel_items, :users,
                    column: :assignee_id,
                    on_delete: :nullify,
                    validate: false
    validate_foreign_key :funnel_items, :users, column: :assignee_id
  end

  def down
    remove_foreign_key :funnel_items, :users, column: :assignee_id if foreign_key_exists?(:funnel_items, :users, column: :assignee_id)
  end
end
