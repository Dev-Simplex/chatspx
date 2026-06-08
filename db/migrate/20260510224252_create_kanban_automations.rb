class CreateKanbanAutomations < ActiveRecord::Migration[7.0]
  def change
    create_table :kanban_automations do |t|
      t.string :name, null: false
      t.bigint :kanban_id, null: false
      t.bigint :kanban_stage_id
      t.string :trigger, null: false
      t.jsonb :conditions, null: false, default: {}
      t.jsonb :actions, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.timestamps null: false
    end

    add_index :kanban_automations, :kanban_id
    add_index :kanban_automations, :kanban_stage_id
    add_index :kanban_automations, :trigger
    add_index :kanban_automations, [:kanban_id, :enabled]

    add_foreign_key :kanban_automations, :kanbans,       on_delete: :cascade
    add_foreign_key :kanban_automations, :kanban_stages, on_delete: :cascade
  end
end
