# frozen_string_literal: true

# Kanban v2 (Fase 2) — definitions of per-funnel custom fields. The VALUES are
# stored in conversations.custom_attributes namespaced as `funnel_<id>_<key>`,
# so there is no separate values table in the MVP. New table only → additive
# and reversible; inert until a funnel defines fields.
class CreateFunnelCustomFields < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_custom_fields do |t|
      t.references :funnel, null: false, foreign_key: true
      t.string  :key, null: false        # namespaced into conversations.custom_attributes
      t.string  :label, null: false
      t.string  :field_type, null: false # text|long_text|number|date|dropdown|checkbox|rating|phone|email|link
      t.jsonb   :options, null: false, default: {}
      t.integer :position, default: 0
      t.boolean :show_on_card, default: false, null: false
      t.timestamps
    end
    add_index :funnel_custom_fields, [:funnel_id, :key], unique: true
    add_index :funnel_custom_fields, [:funnel_id, :position]
  end
end
