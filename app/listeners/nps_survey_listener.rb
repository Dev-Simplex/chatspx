class NpsSurveyListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    return unless conversation.resolved?

    inbox = Inbox.find(conversation.inbox_id)
    return unless inbox.nps_survey_enabled?

    nps_config = inbox.nps_config || {}
    mode = nps_config['mode'] || 'auto'
    return unless %w[auto both].include?(mode)

    NpsSurveyService.new(conversation: conversation, mode: 'auto').perform
  rescue StandardError => e
    Rails.logger.error "Failed to send NPS survey for conversation #{conversation.id}: #{e.message}"
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]

    # If an agent sends a message, dismiss any active NPS (agent took over the conversation)
    if message.outgoing? && !message.content_attributes&.dig('nps_survey')
      dismiss_active_nps(message.conversation)
      return
    end

    return unless message.incoming?

    # Check if there's an active NPS survey waiting for response
    NpsSurveys::ResponseBuilder.new(message: message).perform
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return unless message.input_nps?

    # Handle widget submissions for NPS
    NpsSurveys::ResponseBuilder.new(message: message).perform
  end

  private

  def dismiss_active_nps(conversation)
    dismissed = conversation.nps_responses
                            .where(status: :sent, answered_at: nil)
                            .update_all(status: NpsResponse.statuses[:dismissed]) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.info "NpsSurveyListener: dismissed #{dismissed} active NPS for conversation #{conversation.id}" if dismissed.positive?
  end
end
