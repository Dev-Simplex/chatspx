class CreateTeamSupervisors < ActiveRecord::Migration[7.1]
  # Aditiva. Supervisão de time (D1): supervisionar NÃO é ser membro — virar membro
  # mudaria contagem do time, canal do chat interno, auto-assign e visibilidade de
  # etiquetas/respostas "de-time". Por isso é tabela própria, e não um role em
  # team_members. Inerte enquanto ninguém for marcado supervisor.
  def up
    create_table :team_supervisors, if_not_exists: true do |t|
      t.bigint :team_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
    end

    # (team, user) único: marcar duas vezes o mesmo supervisor no mesmo time é ruído.
    add_index :team_supervisors, %i[team_id user_id], unique: true, if_not_exists: true
    # a pergunta quente é "quais times este usuário supervisiona?" (uma vez por request)
    add_index :team_supervisors, :user_id, if_not_exists: true

    add_foreign_key :team_supervisors, :teams, on_delete: :cascade unless foreign_key_exists?(:team_supervisors, :teams)
    add_foreign_key :team_supervisors, :users, on_delete: :cascade unless foreign_key_exists?(:team_supervisors, :users)
  end

  def down
    drop_table :team_supervisors
  end
end
