# frozen_string_literal: true

# Kanban: cartões de TAREFA/LEMBRETE — funnel_items que não pertencem a uma
# conversa (tarefa interna para alguém fazer). conversation_id passa a ser
# opcional e o item ganha título/descrição/responsável próprios.
# O índice único (conversation_id, funnel_id) segue válido: no Postgres NULLs são
# distintos, então múltiplos cartões de tarefa (conversation_id = NULL) coexistem.
class AddTaskCardSupportToFunnelItems < ActiveRecord::Migration[7.1]
  def up
    change_column_null :funnel_items, :conversation_id, true
    add_column :funnel_items, :title, :string
    add_column :funnel_items, :description, :text
    add_column :funnel_items, :assignee_id, :bigint
    add_index :funnel_items, :assignee_id
  end

  def down
    remove_index :funnel_items, :assignee_id
    remove_column :funnel_items, :assignee_id
    remove_column :funnel_items, :description
    remove_column :funnel_items, :title
    # Não re-aplicamos NOT NULL para não quebrar cartões de tarefa já criados.
  end
end
