class NpsSurveyListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    return unless auto_nps_eligible?(conversation)

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

  # Elegibilidade do disparo AUTOMATICO (na resolucao). Extraido do listener so pra manter o
  # metodo do evento legivel — a ordem das checagens e a de antes, com o freio de grupo somado.
  #
  # Grupo de WhatsApp nao recebe pesquisa automatica: "de 0 a 10, quanto voce nos recomendaria?"
  # num grupo de trabalho e ruido, qualquer participante responde por todos e a nota fica amarrada
  # ao contato-grupo. Nao e hipotese — ja existem 2 NpsResponse dentro de grupo nesta base.
  # O disparo MANUAL (agente clicando "enviar NPS", nps_responses_controller) segue permitido: e
  # acao deliberada de humano, e barra-la em silencio seria pior que o bug.
  # Ver Conversation#group? — ponto unico de verdade, nunca reimplementar a heuristica de @g.us.
  def auto_nps_eligible?(conversation)
    return false unless conversation.resolved?
    return false if conversation.group?

    inbox = Inbox.find(conversation.inbox_id)
    return false unless inbox.nps_survey_enabled?

    mode = (inbox.nps_config || {})['mode'] || 'auto'
    %w[auto both].include?(mode)
  end

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
