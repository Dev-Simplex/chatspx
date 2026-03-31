class CsatSurveyListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]

    return unless conversation.resolved?

    begin
      CsatSurveyService.new(conversation: conversation).perform
    rescue StandardError => e
      Rails.logger.error "Failed to send CSAT survey for conversation #{conversation.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return unless message.input_csat?

    CsatSurveys::ResponseBuilder.new(message: message).perform
  end
end
