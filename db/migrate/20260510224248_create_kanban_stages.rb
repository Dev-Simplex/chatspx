class CreateKanbanStages < ActiveRecord::Migration[7.0]
  def change
    create_table :kanban_stages do |t|
      t.string :name, null: false
      t.string :color, limit: 16
      t.bigint :kanban_id, null: false
      t.integer :position, null: false, default: 0
      t.string :automation_type           # 'open' | 'resolved' | nil
      t.integer :rot_after_days           # null = sem aging
      t.integer :wip_limit                # null = sem limite
      t.string :won_loss_type             # 'won' | 'loss' | nil
      t.bigint :default_message_template_id
      t.integer :probability              # 0..100
      t.jsonb :settings, null: false, default: {}
      t.timestamps null: false
    end

    add_index :kanban_stages, :kanban_id
    add_index :kanban_stages, [:kanban_id, :position]
    add_index :kanban_stages, [:kanban_id, :automation_type],
              unique: true, where: 'automation_type IS NOT NULL',
              name: 'index_kanban_stages_unique_automation'
    add_index :kanban_stages, [:kanban_id, :won_loss_type],
              unique: true, where: 'won_loss_type IS NOT NULL',
              name: 'index_kanban_stages_unique_won_loss'

    add_foreign_key :kanban_stages, :kanbans, on_delete: :cascade
  end
end
