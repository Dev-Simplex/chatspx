# frozen_string_literal: true

# Cancels every active enrollment of a conversation — used by exit conditions
# (customer replied, conversation resolved). Mirrors
# Spx::Tozi::ReactivationCadenceService.cancel_pending. Because AdvanceService only
# creates a ScheduledMessage at send time (never far in advance), cancelling the
# enrollment is enough to stop all future steps — no orphaned scheduled messages.
class MessageSequences::CancelService
  def self.cancel_for(conversation, reason: nil)
    new(conversation: conversation, reason: reason).perform
  end

  def initialize(conversation:, reason: nil)
    @conversation = conversation
    @reason = reason
  end

  def perform
    return if @conversation.blank?

    MessageSequenceEnrollment.active
                             .where(conversation_id: @conversation.id)
                             .find_each do |enrollment|
      enrollment.update!(status: :cancelled, next_run_at: nil)
    end
  end
end
