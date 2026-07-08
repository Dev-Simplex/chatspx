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

    # Se um AGENTE envia mensagem, dismissa a pesquisa (agente assumiu a conversa).
    # Mas nao dismissar as mensagens do proprio fluxo NPS (pergunta, aviso de resposta
    # invalida, agradecimento) — senao a pesquisa e cancelada e reenviada em duplicidade.
    if message.outgoing? && !nps_system_message?(message)
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

  # Mensagens geradas pelo proprio NPS: a pergunta (nps_survey) e as mensagens de
  # sistema (aviso de invalida, agradecimento) marcadas com nps_survey_system.
  def nps_system_message?(message)
    attrs = message.content_attributes || {}
    attrs['nps_survey'].present? || attrs['nps_survey_system'].present?
  end

  def dismiss_active_nps(conversation)
    dismissed = conversation.nps_responses
                            .where(status: :sent, answered_at: nil)
                            .update_all(status: NpsResponse.statuses[:dismissed]) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.info "NpsSurveyListener: dismissed #{dismissed} active NPS for conversation #{conversation.id}" if dismissed.positive?
  end
end
