# frozen_string_literal: true

class KanbanCaptainFeedback < ApplicationRecord
  belongs_to :kanban_item
  belongs_to :suggested_stage, class_name: 'KanbanStage', optional: true
  belongs_to :actual_stage,    class_name: 'KanbanStage', optional: true

  FEEDBACKS = %w[approve override pending].freeze

  validates :ai_feedback, inclusion: { in: FEEDBACKS, allow_nil: true }
  validates :confidence,  numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  scope :approved, -> { where(ai_feedback: 'approve') }
  scope :overridden, -> { where(ai_feedback: 'override') }
end
