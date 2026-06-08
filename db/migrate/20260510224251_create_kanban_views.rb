class CreateKanbanViews < ActiveRecord::Migration[7.0]
  def change
    create_table :kanban_views do |t|
      t.string :name, null: false
      t.bigint :kanban_id, null: false
      t.bigint :user_id
      t.boolean :is_shared, null: false, default: false
      t.jsonb :filters, null: false, default: {}
      t.jsonb :sort, null: false, default: { 'by' => 'last_activity_at', 'dir' => 'desc' }
      t.jsonb :settings, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps null: false
    end

    add_index :kanban_views, :kanban_id
    add_index :kanban_views, :user_id
    add_index :kanban_views, [:kanban_id, :user_id]
    add_index :kanban_views, [:kanban_id, :is_shared]

    add_foreign_key :kanban_views, :kanbans, on_delete: :cascade
    add_foreign_key :kanban_views, :users,   on_delete: :cascade
  end
end
