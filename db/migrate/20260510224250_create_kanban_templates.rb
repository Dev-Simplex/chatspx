class CreateKanbanTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :kanban_templates do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :description, limit: 500
      t.string :vertical
      t.string :icon, limit: 32
      t.string :color, limit: 16
      t.string :locale, null: false, default: 'pt-BR'
      t.integer :version, null: false, default: 1
      t.jsonb :stages_config, null: false, default: []
      t.jsonb :sample_cards, null: false, default: []
      t.jsonb :automations_config, null: false, default: []
      t.boolean :is_official, null: false, default: true
      t.bigint :account_id
      t.timestamps null: false
    end

    add_index :kanban_templates, :slug, unique: true
    add_index :kanban_templates, :vertical
    add_index :kanban_templates, :locale
    add_index :kanban_templates, :account_id

    add_foreign_key :kanban_templates, :accounts, on_delete: :cascade
    # Agora que kanban_templates existe, adicionar FK kanbans.template_id -> kanban_templates.id
    add_foreign_key :kanbans, :kanban_templates, column: :template_id, on_delete: :nullify
  end
end
