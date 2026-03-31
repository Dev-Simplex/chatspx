class NpsSurveyListener < BaseListener
  def conversation_status_changed(event) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    Rails.logger.info 'NpsSurveyListener: conversation_status_changed event received'

    conversation = extract_conversation_and_account(event)[0]

    Rails.logger.info "NpsSurveyListener: conversation_status_changed for conversation #{conversation.id}, " \
                      "status: #{conversation.status}, inbox_id: #{conversation.inbox_id}"

    return unless conversation.resolved?

    Rails.logger.debug { "NpsSurveyListener: conversation #{conversation.id} is resolved, checking NPS config" }

    # Reload inbox to ensure we have the latest NPS configuration
    # Use find to ensure we get fresh data from database
    inbox = Inbox.find(conversation.inbox_id)

    Rails.logger.debug { "NpsSurveyListener: inbox #{inbox.id}, nps_survey_enabled: #{inbox.nps_survey_enabled}" }

    # Check if NPS is enabled for this inbox first
    unless inbox.nps_survey_enabled?
      Rails.logger.debug { "NpsSurveyListener: NPS not enabled for inbox #{inbox.id}" }
      return
    end

    # Only send automatically if mode is 'auto' or 'both'
    nps_config = inbox.nps_config || {}
    mode = nps_config['mode'] || 'auto'

    Rails.logger.debug { "NpsSurveyListener: NPS mode is '#{mode}'" }

    unless %w[auto both].include?(mode)
      Rails.logger.debug { "NpsSurveyListener: Mode '#{mode}' does not allow automatic sending" }
      return
    end

    Rails.logger.info "NpsSurveyListener: Attempting to send NPS survey for conversation #{conversation.id}"

    begin
      NpsSurveyService.new(conversation: conversation, mode: 'auto').perform
      Rails.logger.info "NpsSurveyListener: Successfully processed NPS survey for conversation #{conversation.id}"
    rescue StandardError => e
      Rails.logger.error "Failed to send NPS survey for conversation #{conversation.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Don't raise - fail silently to avoid breaking the conversation status change
    end
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
