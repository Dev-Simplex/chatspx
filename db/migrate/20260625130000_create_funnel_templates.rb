# frozen_string_literal: true

# Kanban v2 (Fase 8) — global catalog of ready-made funnel templates (stages +
# custom fields). Account-agnostic; an account creates a funnel FROM a template.
class CreateFunnelTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_templates do |t|
      t.string  :name, null: false
      t.string  :description
      t.string  :slug, null: false
      t.jsonb   :definition, null: false, default: {}
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :funnel_templates, :slug, unique: true
  end
end
