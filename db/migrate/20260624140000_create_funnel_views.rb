# frozen_string_literal: true

# Kanban v2 (Fase 3) — saved views: a named recorte of a funnel board (filters
# + view mode) owned by a user, optionally shared with the account.
# Named funnel_views (not kanban_views) because a legacy `kanban_views` table
# from the old kanban feature already exists. New table → additive, reversible.
class CreateFunnelViews < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_views do |t|
      t.references :account, null: false, foreign_key: true
      t.references :funnel, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string  :name, null: false
      t.jsonb   :filters, null: false, default: {}
      t.string  :view_mode, null: false, default: 'kanban'
      t.boolean :is_shared, null: false, default: false
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :funnel_views, [:account_id, :funnel_id]
  end
end
