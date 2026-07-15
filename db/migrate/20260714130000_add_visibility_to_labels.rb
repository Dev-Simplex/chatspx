# Etiquetas para todos + visibilidade (pública/privada/de time).
#
# Porquê (padrão do fork): até aqui só admins geriam o catálogo de etiquetas e
# uma etiqueta não tinha dono nem escopo de visibilidade. Espelhando o precedente
# de Macro (visibility + created_by), adicionamos:
#   - `visibility` (0 = everyone/pública — mantém o comportamento atual das labels
#     existentes, que ficam públicas e órfãs);
#   - `created_by` (autor; nullify ao apagar o usuário — vira etiqueta órfã que só
#     admin gerencia);
#   - `team` (escopo de time quando visibility = team; nullify ao apagar o time,
#     complementado por um cleanup no Team que rebaixa a label para everyone).
# Aditivo/nullable: baixo risco, sem backfill (não há como inferir o autor histórico).
class AddVisibilityToLabels < ActiveRecord::Migration[7.1]
  def up
    add_column :labels, :visibility, :integer, default: 0, null: false # 0 = everyone (público)
    add_reference :labels, :created_by, null: true,
                                        foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :labels, :team, null: true,
                                  foreign_key: { to_table: :teams, on_delete: :nullify }
    add_index :labels, %i[account_id visibility], name: 'index_labels_on_account_and_visibility'
  end

  def down
    remove_index :labels, name: 'index_labels_on_account_and_visibility', if_exists: true
    remove_reference :labels, :team, if_exists: true
    remove_reference :labels, :created_by, if_exists: true
    remove_column :labels, :visibility, if_exists: true
  end
end
