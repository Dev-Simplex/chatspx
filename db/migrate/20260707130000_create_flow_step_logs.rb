# frozen_string_literal: true

# Per-step observability for the Flow engine. Every node the Flows::RunnerService executes
# writes ONE row here: what ran (node_id, action_name), how it ended (status —
# success/failed/skipped), which exit a condition/router took (branch_key), the typed error
# (error_code + error_message) when it failed, and how long it took (duration_ms). Until now
# a node error was a silent `rescue` inside Flows::ActionService#execute with no trace; the
# runner now records it best-effort (a logging failure never breaks the walk).
#
# Denormalised flow_id/account_id keep the "which flow / which account misbehaved" queries a
# single index hit. conversation_id and flow_run_id are nullable: a step can be logged before
# a FlowRun is materialised (linear flows never create one — see FlowRun) and, defensively,
# outside a conversation. Mirrors the create_flow_runs migration's shape/style.
class CreateFlowStepLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :flow_step_logs do |t|
      t.references :flow, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: true, foreign_key: true
      t.references :flow_run, null: true, foreign_key: true
      t.string   :node_id                            # the visited node (definition-local id)
      t.string   :action_name                        # set for `action` nodes; nil otherwise
      t.integer  :status, null: false, default: 0    # success / failed / skipped
      t.string   :branch_key                         # exit a condition/router took (true/false/…)
      t.string   :error_code                         # typed, human-triageable (unknown_action, …)
      t.text     :error_message                      # exception message (failed) / skip reason
      t.integer  :duration_ms                        # wall time of the step
      t.jsonb    :metadata, null: false, default: {} # room for future per-node context
      t.timestamps
    end

    add_index :flow_step_logs, :status
    add_index :flow_step_logs, :created_at
  end
end
