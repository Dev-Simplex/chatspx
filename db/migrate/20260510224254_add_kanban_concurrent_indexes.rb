class AddKanbanConcurrentIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :kanban_items, :aging_days, algorithm: :concurrently
    add_index :kanban_items, [:kanban_id, :created_at], algorithm: :concurrently
  end
end
