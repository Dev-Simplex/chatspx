# frozen_string_literal: true

# Persistent run-state for a Flow execution — the backbone of Fase 2 (wait/schedule, drip,
# compliance). Fase 1's Flows::RunnerService walked the graph linearly and synchronously,
# with no way to suspend/resume. A FlowRun is materialised LAZILY, only when a `wait` node
# pauses the walk: it records where the walk stopped (current_node_id = the node to resume
# at), when to resume (wait_until) and the accumulated state/variables (context). Flows
# without a wait never create a row — the linear path is untouched.
#
# Mirrors message_sequence_enrollments (the plano mestre says to copy it): a partial unique
# index allows only ONE in-flight run (active|waiting) per (flow, conversation), while still
# permitting a fresh run after the previous one completes or fails. `contact_id` is stored
# denormalised (compliance/drip queries) but the dedup key stays on the conversation, faithful
# to the enrollment and to the conversation-anchored engine ("conversa em primeiro lugar").
class CreateFlowRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :flow_runs do |t|
      t.references :flow, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :contact, null: true, foreign_key: true
      t.integer  :status, null: false, default: 0 # active / waiting / completed / failed
      t.string   :current_node_id                 # node to resume AT (successor of the wait)
      t.datetime :wait_until                       # when a waiting run becomes due
      t.jsonb    :context, null: false, default: {} # accumulated variables / trigger payload
      t.timestamps
    end

    add_index :flow_runs, [:status, :wait_until]
    add_index :flow_runs,
              [:flow_id, :conversation_id],
              unique: true,
              where: 'status IN (0, 1)',
              name: 'index_active_flow_run_per_flow_conversation'
  end
end
