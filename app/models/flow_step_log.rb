# frozen_string_literal: true

# == Schema Information
#
# Table name: flow_step_logs
#
#  id              :bigint           not null, primary key
#  action_name     :string
#  branch_key      :string
#  duration_ms     :integer
#  error_code      :string
#  error_message   :text
#  metadata        :jsonb            not null
#  node_id         :string
#  status          :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint
#  flow_id         :bigint           not null
#  flow_run_id     :bigint
#
# Indexes
#
#  index_flow_step_logs_on_account_id      (account_id)
#  index_flow_step_logs_on_conversation_id (conversation_id)
#  index_flow_step_logs_on_created_at      (created_at)
#  index_flow_step_logs_on_flow_id         (flow_id)
#  index_flow_step_logs_on_flow_run_id     (flow_run_id)
#  index_flow_step_logs_on_status          (status)
#
# One row per node the Flows::RunnerService executes — the audit trail the engine lacked
# (node errors used to be a silent rescue). Records status (success/failed/skipped),
# duration_ms, the branch a condition/router took (branch_key) and, on failure, a typed
# error_code + error_message. Writes are best-effort: the runner rescues any insert failure
# so observability can never break the flow. flow_run_id is set only once a FlowRun exists
# (flows without a `wait` never create one); conversation_id is denormalised for triage.
class FlowStepLog < ApplicationRecord
  belongs_to :flow
  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :flow_run, optional: true

  # `failed` / `success` / `skipped` scopes come for free from the enum.
  enum status: { success: 0, failed: 1, skipped: 2 }

  # Most-recent first — the natural order for a "what did this flow just do" view.
  scope :recent, -> { order(created_at: :desc) }
  scope :for_flow, ->(flow) { where(flow: flow) }
  scope :for_conversation, ->(conversation) { where(conversation: conversation) }
end
