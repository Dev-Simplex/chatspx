class Captain::Tools::HandoffTool < Captain::Tools::BasePublicTool
  # Gatilho POSITIVO: o handoff não é só pra "quando você não consegue" — é o passo normal
  # de passar um lead qualificado pra uma pessoa fechar. A descrição antiga ("when unable to
  # assist further") fazia a IA quase nunca chamar o tool (uma IA que está atendendo bem nunca
  # se considera "unable to assist"), então nenhum lead chegava ao humano.
  description 'Hand off the conversation to a human agent only when the customer requests human assistance, ' \
              'accepts an offer to speak with a human, an account-specific guideline requires transfer, or the ' \
              'request requires an action the assistant cannot perform. Continue assisting until a human takes over.'
  param :reason, type: 'string', desc: 'The reason why handoff is needed (optional)', required: false
  param :team_id, type: 'string', desc: 'ID of the team to route the conversation to (optional)', required: false

  # RubyLLM::Tool delega description da instância para a classe — override de instância,
  # DINÂMICO por conta (tools são instanciadas a cada run: assistant.agent → agent_tools →
  # .new(self), então chega sempre fresco no LLM):
  #  - modo "time fixo" (account.custom_attributes['handoff_team_id'] setado): a IA NÃO
  #    escolhe o time — todo handoff cai no time configurado. Não enumera
  #    times (senão a IA tentaria escolher à toa).
  #  - modo "IA decide" (sem config, DEFAULT): enumera os times pra IA rotear pelo assunto
  #    (param team_id) — comportamento pra clientes que querem a IA definindo o setor.
  def description
    base = self.class.description
    return base.to_s if fixed_handoff_team?

    teams = @assistant.account.teams.order(:id).map { |t| "#{t.id}: #{t.name}" }.join('; ')
    teams.present? ? "#{base} Times disponíveis (id: nome) — #{teams}. Roteie pelo assunto passando o team_id." : base.to_s
  end

  def fixed_handoff_team?
    @assistant.account.custom_attributes&.dig('handoff_team_id').present?
  end

  def perform(tool_context, reason: nil, team_id: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    # Idempotência: se a conversa JÁ está aguardando humano, não refaz o handoff (senão gera
    # uma 2ª nota privada/dossiê duplicado e reseta o marcador a cada mensagem do cliente na espera).
    if conversation.custom_attributes&.dig('aguardando_humano_desde').present?
      return 'Esta conversa JÁ está aguardando atendimento humano — o handoff já foi feito. ' \
             'NÃO chame o handoff de novo nem registre outro dossiê. Responda dúvidas NOVAS ' \
             'normalmente; se for só cobrança de pressa/ansiedade sem pergunta nova, responda [IGNORAR].'
    end

    # Log the handoff with reason
    log_tool_usage('tool_handoff', {
                     conversation_id: conversation.id,
                     reason: reason || 'Agent requested handoff'
                   })

    trigger_handoff(tool_context, conversation, reason, team_id)

    'Time humano acionado: dossiê registrado e conversa marcada como aguardando atendente. ' \
      'Na SUA resposta, avise o cliente que uma pessoa do time vai assumir e CONTINUE atendendo ' \
      'normalmente até o atendente assumir de fato.'
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Failed to handoff conversation'
  end

  private

  # Modelo A (decisão Paulo): a IA NÃO solta a conversa no handoff — segue dona e
  # respondendo até um humano PUXAR a atribuição. A lógica (abrir a conversa, rotear pro
  # time, marcar `aguardando_humano_desde`, distribuir) vive no HumanHandoffService, fonte
  # única reusada também pelo FollowupJob quando as cutucadas in-window esgotam.
  def trigger_handoff(tool_context, conversation, reason, team_id = nil)
    service = Captain::Conversation::HumanHandoffService.new(
      conversation: conversation, assistant: @assistant, reason: reason, team_id: team_id
    )
    service.perform

    # Session capture attributes the run to this note so agents can inspect the
    # generation path on the handoff reason instead of the canned follow-up message.
    if service.handoff_note.present?
      metadata = tool_context.state[:cw_metadata] ||= {}
      metadata[:handoff_note_id] = service.handoff_note.id
    end
  end

  # TODO: Future enhancement
  # This tool could be enhanced to:
  # 1. Set conversation priority based on handoff reason
  # 2. Add metadata for intelligent agent assignment
  # 3. Support escalation levels (L1 -> L2 -> L3)
  #
  # Example future signature:
  # param :priority, type: 'string', desc: 'Priority level (low/medium/high/urgent)', required: false
  # param :escalation_level, type: 'string', desc: 'Support level (L1/L2/L3)', required: false
end
