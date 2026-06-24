# frozen_string_literal: true

# Kanban v2 (Fase 5) — declarative automations ("when → conditions → then") per
# funnel. Named funnel_automations (the legacy kanban system already owns
# kanban_automations). New table → additive, reversible; inert until a manager
# creates a rule.
class CreateFunnelAutomations < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_automations do |t|
      t.references :funnel, null: false, foreign_key: true
      t.references :funnel_stage, foreign_key: true # optional: scope to one column
      t.string  :name, null: false
      t.jsonb   :trigger, null: false, default: {}   # { event: 'item_entered_stage'|'time_in_stage', hours: 24 }
      t.jsonb   :conditions, null: false, default: [] # [{ field:, op:, value: }]
      t.jsonb   :actions, null: false, default: []    # [{ type:'move', stage_id: }, { type:'assign', assignee_id: }, ...]
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :funnel_automations, [:funnel_id, :active]
  end
end
