# frozen_string_literal: true

# Follow-up drip (Módulo A, A3) — stops a conversation's sequences when an exit
# condition fires: the customer replies (incoming message) or the conversation
# reaches a configured status (e.g. resolved). Cancellation is per-enrollment and
# honors each sequence's own exit_conditions, so unrelated sequences keep running.
#
# Runs for every account on the instance (AsyncDispatcher), so each handler is
# rescue-wrapped and no-ops cheaply when there are no matching enrollments.
class MessageSequences::ExitListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    return if message.nil? || message.activity? || !message.incoming?

    conversation = message.conversation
    return if conversation.nil?

    cancel_matching(conversation) { |enrollment| enrollment.message_sequence.cancel_on_customer_reply? }
  rescue StandardError => e
    Rails.logger.error("[MessageSequences::ExitListener] message_created: #{e.message}")
  end

  def conversation_status_changed(event)
    conversation, = extract_conversation_and_account(event)
    return if conversation.nil?

    status = conversation.status.to_s
    cancel_matching(conversation) { |enrollment| enrollment.message_sequence.exit_status == status }
  rescue StandardError => e
    Rails.logger.error("[MessageSequences::ExitListener] conversation_status_changed: #{e.message}")
  end

  private

  def cancel_matching(conversation)
    MessageSequenceEnrollment.active
                             .where(conversation_id: conversation.id)
                             .includes(:message_sequence)
                             .find_each do |enrollment|
      enrollment.update!(status: :cancelled, next_run_at: nil) if yield(enrollment)
    end
  end
end
