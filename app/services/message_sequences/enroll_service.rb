# frozen_string_literal: true

# Enrolls a conversation into a sequence: creates the enrollment and schedules the
# first step. Idempotent — a conversation already moving through the sequence is a
# no-op (mirrors ReactivationCadenceService#cadence_already_scheduled?). The partial
# unique index is the last line of defense against a race.
class MessageSequences::EnrollService
  def initialize(sequence:, conversation:, enrolled_by: nil)
    @sequence = sequence
    @conversation = conversation
    @enrolled_by = enrolled_by
  end

  def perform
    return if @sequence.blank? || @conversation.blank?
    return unless @sequence.active?

    first_step = @sequence.steps.first
    return if first_step.blank?
    return if already_enrolled?

    MessageSequenceEnrollment.create!(
      message_sequence: @sequence,
      conversation: @conversation,
      enrolled_by: @enrolled_by,
      status: :active,
      current_step_position: first_step.position,
      next_run_at: first_step.delay_minutes.minutes.from_now
    )
  rescue ActiveRecord::RecordNotUnique
    nil # lost the race with a concurrent active enrollment — idempotent no-op
  end

  private

  def already_enrolled?
    @sequence.enrollments.active.exists?(conversation_id: @conversation.id)
  end
end
