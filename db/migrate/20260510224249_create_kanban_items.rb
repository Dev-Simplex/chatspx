class CreateKanbanItems < ActiveRecord::Migration[7.0]
  def change
    create_table :kanban_items do |t|
      t.bigint :kanban_id,        null: false
      t.bigint :kanban_stage_id,  null: false
      t.bigint :conversation_id,  null: false
      t.bigint :moved_by_id
      t.timestamp :last_stage_change_at
      t.timestamp :aging_calculated_at
      t.integer :aging_days, default: 0
      t.decimal :position, precision: 20, scale: 10, default: 0
      t.string :won_reason
      t.string :loss_reason
      t.text :note
      t.jsonb :metadata, null: false, default: {}
      t.timestamps null: false
    end

    add_index :kanban_items, :kanban_id
    add_index :kanban_items, :kanban_stage_id
    add_index :kanban_items, :conversation_id
    add_index :kanban_items, :moved_by_id
    add_index :kanban_items, [:conversation_id, :kanban_id], unique: true, name: 'idx_kanban_items_unique'
    add_index :kanban_items, [:kanban_id, :kanban_stage_id, :position], name: 'idx_kanban_items_stage_pos'
    add_index :kanban_items, [:kanban_stage_id, :position], name: 'idx_kanban_items_pos_keyset'
    add_index :kanban_items, :last_stage_change_at

    add_foreign_key :kanban_items, :kanbans,        on_delete: :cascade
    add_foreign_key :kanban_items, :kanban_stages,  on_delete: :restrict
    add_foreign_key :kanban_items, :conversations,  on_delete: :cascade
    add_foreign_key :kanban_items, :users, column: :moved_by_id, on_delete: :nullify
  end
end
