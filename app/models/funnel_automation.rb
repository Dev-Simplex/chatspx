# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_automations
#
#  id              :bigint           not null, primary key
#  actions         :jsonb            not null
#  active          :boolean          default(TRUE), not null
#  conditions      :jsonb            not null
#  name            :string           not null
#  trigger         :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  funnel_id       :bigint           not null
#  funnel_stage_id :bigint
#
# Kanban v2 (Fase 5): a declarative "when → conditions → then" rule on a funnel.
class FunnelAutomation < ApplicationRecord
  EVENTS = %w[item_entered_stage time_in_stage].freeze
  ACTION_TYPES = %w[move assign tag webhook enroll_in_sequence].freeze
  CONDITION_OPS = %w[eq neq present blank includes].freeze

  belongs_to :funnel
  belongs_to :funnel_stage, optional: true

  validates :name, presence: true
  validate :trigger_event_supported

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:created_at) }
  scope :for_event, ->(event) { where("trigger ->> 'event' = ?", event) }

  def event
    trigger.is_a?(Hash) ? trigger['event'] : nil
  end

  def trigger_hours
    value = trigger.is_a?(Hash) ? trigger['hours'] : nil
    value.to_i if value.present?
  end

  # When set, the rule only fires for cards entering / sitting in this stage.
  def scoped_stage_id
    funnel_stage_id
  end

  private

  def trigger_event_supported
    return if EVENTS.include?(event)

    errors.add(:trigger, "event must be one of #{EVENTS.join(', ')}")
  end
end
