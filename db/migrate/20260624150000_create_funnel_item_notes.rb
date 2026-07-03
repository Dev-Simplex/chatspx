# frozen_string_literal: true

# Kanban v2 (Fase 4) — internal notes per card (the card's memory / handoff
# log), separate from the customer-facing chat. New table → additive, reversible.
class CreateFunnelItemNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_item_notes do |t|
      t.references :funnel_item, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.text :content, null: false
      t.timestamps
    end
    add_index :funnel_item_notes, [:funnel_item_id, :created_at]
  end
end
