# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_automations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  kanban_id       :bigint           not null
#  kanban_stage_id :bigint
#  trigger         :string           not null
#  conditions      :jsonb            default({})
#  actions         :jsonb            default([])
#  enabled         :boolean          default(true), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class KanbanAutomation < ApplicationRecord
  TRIGGERS = %w[item_entered_stage item_left_stage item_aging_threshold].freeze

  ACTION_TYPES = %w[send_template assign add_label move create_task].freeze

  belongs_to :kanban
  belongs_to :kanban_stage, optional: true

  validates :name, presence: true
  validates :trigger, presence: true, inclusion: { in: TRIGGERS }
  validate :actions_have_valid_types

  scope :enabled, -> { where(enabled: true) }
  scope :by_trigger, ->(trigger) { where(trigger: trigger) }
  scope :for_stage, ->(stage_id) { where(kanban_stage_id: [stage_id, nil]) }

  private

  def actions_have_valid_types
    return if actions.blank?

    actions.each do |action|
      next if action.is_a?(Hash) && ACTION_TYPES.include?(action['type'] || action[:type])

      errors.add(:actions, "invalid action: #{action}")
      break
    end
  end
end
