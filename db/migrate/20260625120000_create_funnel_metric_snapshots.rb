# frozen_string_literal: true

# Kanban v2 (Fase 6) — daily per-funnel metric snapshots, the foundation for
# baselines / trends ("vs yesterday", "vs average"). New table → additive,
# reversible. One row per funnel per day.
class CreateFunnelMetricSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_metric_snapshots do |t|
      t.references :funnel, null: false, foreign_key: true
      t.date  :captured_on, null: false
      t.jsonb :metrics, null: false, default: {}
      t.timestamps
    end
    add_index :funnel_metric_snapshots, [:funnel_id, :captured_on], unique: true
  end
end
