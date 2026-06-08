class CreateKanbans < ActiveRecord::Migration[7.0]
  def change
    create_table :kanbans do |t|
      t.string :name, null: false
      t.string :description, limit: 500
      t.string :color, limit: 16
      t.bigint :account_id, null: false
      t.bigint :team_id
      t.jsonb :inbox_ids, null: false, default: []
      t.integer :position, null: false, default: 0
      t.jsonb :settings, null: false, default: {}
      t.timestamp :archived_at
      t.bigint :created_by_id
      t.bigint :template_id
      t.timestamps null: false
    end

    add_index :kanbans, :account_id
    add_index :kanbans, :team_id
    add_index :kanbans, :inbox_ids, using: :gin
    add_index :kanbans, [:account_id, :archived_at]
    add_index :kanbans, :template_id

    add_foreign_key :kanbans, :accounts, column: :account_id
    add_foreign_key :kanbans, :teams,    column: :team_id,       on_delete: :nullify
    add_foreign_key :kanbans, :users,    column: :created_by_id, on_delete: :nullify
    # FK template_id e adicionada em CreateKanbanTemplates (depois de criar a tabela).
  end
end
