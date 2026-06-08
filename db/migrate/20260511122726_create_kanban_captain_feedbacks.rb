class CreateKanbanCaptainFeedbacks < ActiveRecord::Migration[7.0]
  def change
    create_table :kanban_captain_feedbacks do |t|
      t.bigint :kanban_item_id, null: false
      t.bigint :suggested_stage_id
      t.bigint :actual_stage_id
      t.string :ai_feedback           # 'approve' | 'override' | 'pending'
      t.decimal :confidence, precision: 5, scale: 4
      t.text :rationale
      t.jsonb :metadata, null: false, default: {}
      t.timestamps null: false
    end

    add_index :kanban_captain_feedbacks, :kanban_item_id
    add_index :kanban_captain_feedbacks, :suggested_stage_id
    add_index :kanban_captain_feedbacks, :actual_stage_id
    add_index :kanban_captain_feedbacks, :ai_feedback
    add_index :kanban_captain_feedbacks, :created_at

    add_foreign_key :kanban_captain_feedbacks, :kanban_items,  on_delete: :cascade
    add_foreign_key :kanban_captain_feedbacks, :kanban_stages, column: :suggested_stage_id, on_delete: :nullify
    add_foreign_key :kanban_captain_feedbacks, :kanban_stages, column: :actual_stage_id,    on_delete: :nullify
  end
end
