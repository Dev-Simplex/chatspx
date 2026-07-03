# frozen_string_literal: true

# Advances ONE enrollment by one step: sends the current step (reusing the tested
# ScheduledMessages pipeline) and either schedules the next step or completes the
# enrollment. Reentrant — `with_lock` + a status/timestamp re-check inside the lock
# prevents a double send when two AdvanceJob ticks overlap. Best-effort: a failure
# is logged and never raised, so one bad enrollment can't break the batch.
class MessageSequences::AdvanceService
  def initialize(enrollment:)
    @enrollment = enrollment
  end

  def perform
    @enrollment.with_lock do
      next unless @enrollment.active?
      next if @enrollment.next_run_at.nil? || @enrollment.next_run_at > Time.current

      step = @enrollment.current_step
      if step.blank?
        @enrollment.update!(status: :completed, current_step_position: nil, next_run_at: nil)
        next
      end

      send_step(step)
      schedule_next(step)
    end
  rescue StandardError => e
    Rails.logger.error("MessageSequences::AdvanceService enrollment=#{@enrollment&.id}: #{e.message}")
    nil
  end

  private

  # Reuse the whole create→send pipeline: scheduling at Time.current fires the
  # SendJob immediately, carrying template_params (HSM) and the channel routing.
  def send_step(step)
    conversation = @enrollment.conversation
    ScheduledMessages::CreateService.new(
      conversation: conversation,
      inbox: conversation.inbox,
      message: step.render_content(conversation),
      scheduled_at: Time.current,
      user: sender,
      template_params: step.template_params.presence
    ).perform
  end

  def schedule_next(step)
    next_step = @enrollment.message_sequence.steps.where('position > ?', step.position).order(:position).first
    if next_step
      @enrollment.update!(current_step_position: next_step.position,
                          next_run_at: next_step.delay_minutes.minutes.from_now)
    else
      @enrollment.update!(status: :completed, current_step_position: nil, next_run_at: nil)
    end
  end

  def sender
    @enrollment.enrolled_by ||
      @enrollment.conversation.assignee ||
      @enrollment.conversation.account.administrators.first
  end
end
