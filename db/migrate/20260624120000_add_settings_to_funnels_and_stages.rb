# frozen_string_literal: true

# Kanban v2 (Fase 1) — additive, reversible foundation for per-stage / per-funnel
# configuration: persisted WIP limits, SLA hours, conditional color rules, stage
# permissions. JSONB default {} so existing serializers/cursors are untouched
# until the `kanban_v2_basics` flag turns the UI on.
class AddSettingsToFunnelsAndStages < ActiveRecord::Migration[7.1]
  def change
    add_column :funnels, :settings, :jsonb, null: false, default: {}
    add_column :funnel_stages, :settings, :jsonb, null: false, default: {}
  end
end
