class CsatSurveyListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]

    return unless conversation.resolved?
    # Conversa que existe só para levar disparo protegido não é atendimento: pesquisar
    # satisfação logo depois de um código de autenticação seria constrangedor e sujaria a
    # nota. Ver Spx::SecretTemplateParams#dispatch_only?.
    return if Spx::SecretTemplateParams.dispatch_only?(conversation)

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
