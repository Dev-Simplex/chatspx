# frozen_string_literal: true

# == Schema Information
#
# Table name: flow_runs
#
#  id              :bigint           not null, primary key
#  context         :jsonb            not null
#  current_node_id :string
#  status          :integer          default(0), not null
#  wait_until      :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  contact_id      :bigint
#  conversation_id :bigint           not null
#  flow_id         :bigint           not null
#
# Persistent state of ONE Flow execution across suspends. Created lazily by
# Flows::RunnerService the first time a `wait` node pauses the walk; it carries the node to
# resume at (current_node_id), when to resume (wait_until) and the accumulated variables
# (context). Flows::ResumeJob picks up `due` runs every minute and hands each back to the
# runner. Lifecycle: active (just built) → waiting (suspended at a wait) → completed (walk
# reached the end) / failed (walk raised). A partial unique index keeps at most one in-flight
# (active|waiting) run per (flow, conversation); a re-run is allowed once it completes/fails.
# Mirrors MessageSequenceEnrollment.
class FlowRun < ApplicationRecord
  # Statuses that count as "in flight" for the partial unique index (status IN (0,1)) and
  # for reusing an existing run on a re-trigger race. Keep in sync with the migration.
  ACTIVE_STATUSES = %w[active waiting].freeze

  belongs_to :flow
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact, optional: true

  enum status: { active: 0, waiting: 1, completed: 2, failed: 3 }

  # Runs whose wait has elapsed — ResumeJob picks these up every minute.
  scope :due, -> { waiting.where('wait_until <= ?', Time.current) }

  # Suspend the walk at a wait node: remember where to resume (node_id) and when
  # (wait_until). Persists a lazily-built run (INSERT) or an existing one (UPDATE) in one
  # shot, so a new run lands directly in :waiting with no transient :active row to leak.
  def suspend!(node_id:, wait_until:)
    update!(status: :waiting, current_node_id: node_id, wait_until: wait_until)
  end

  # Walk reached the end — clear the resume pointers so the row can't be picked up again.
  def complete!
    update!(status: :completed, current_node_id: nil, wait_until: nil)
  end
  alias finish! complete!

  # Walk raised — record the terminal state and stop retrying (drops out of .due).
  def fail!
    update!(status: :failed, wait_until: nil)
  end
end
