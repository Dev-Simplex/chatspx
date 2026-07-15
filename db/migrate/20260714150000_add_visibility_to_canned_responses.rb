# Respostas prontas para todos + visibilidade (pública/privada/de time).
#
# Porquê (padrão do fork): hoje qualquer membro logado cria/edita/exclui qualquer
# resposta pronta e uma resposta não tem dono nem escopo. Espelhando o precedente
# das Etiquetas (que por sua vez seguem Macro: visibility + created_by), adicionamos:
#   - `visibility` (0 = everyone/pública — mantém o comportamento atual das respostas
#     existentes, que ficam públicas e órfãs);
#   - `created_by` (autor; nullify ao apagar o usuário — vira resposta órfã que só
#     admin re-escopa);
#   - `team` (escopo de time quando visibility = team; nullify ao apagar o time,
#     complementado por um cleanup no Team que rebaixa a resposta para everyone).
# Aditivo/nullable: baixo risco, sem backfill (não há como inferir o autor histórico).
# A tabela é id: :serial (PK integer legada); as FKs novas são bigint apontando para
# users/teams bigint — ok, independente do PK serial.
class AddVisibilityToCannedResponses < ActiveRecord::Migration[7.1]
  def up
    add_column :canned_responses, :visibility, :integer, default: 0, null: false # 0 = everyone (pública)
    add_reference :canned_responses, :created_by, null: true,
                                                  foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :canned_responses, :team, null: true,
                                            foreign_key: { to_table: :teams, on_delete: :nullify }
    add_index :canned_responses, %i[account_id visibility], name: 'index_canned_responses_on_account_and_visibility'
  end

  def down
    remove_index :canned_responses, name: 'index_canned_responses_on_account_and_visibility', if_exists: true
    remove_reference :canned_responses, :team, if_exists: true
    remove_reference :canned_responses, :created_by, if_exists: true
    remove_column :canned_responses, :visibility, if_exists: true
  end
end
