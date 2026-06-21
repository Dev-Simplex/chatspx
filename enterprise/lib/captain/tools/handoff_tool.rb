class Captain::Tools::HandoffTool < Captain::Tools::BasePublicTool
  description 'Hand off the conversation to a human agent when unable to assist further'
  param :reason, type: 'string', desc: 'The reason why handoff is needed (optional)', required: false
  param :team_id, type: 'string', desc: 'ID of the team to route the conversation to (optional)', required: false

  # RubyLLM::Tool delega description da instância para a classe — override de instância
  # enumera os times da conta (tools são instanciadas a cada run: assistant.agent →
  # agent_tools → .new(self)), então a lista chega sempre fresca no LLM.
  def description
    teams = @assistant.account.teams.order(:id).map { |t| "#{t.id}: #{t.name}" }.join('; ')
    base = self.class.description
    teams.present? ? "#{base}. Available teams (id: name) — #{teams}" : base.to_s
  end

  def perform(tool_context, reason: nil, team_id: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    # Log the handoff with reason
    log_tool_usage('tool_handoff', {
                     conversation_id: conversation.id,
                     reason: reason || 'Agent requested handoff'
                   })

    trigger_handoff(conversation, reason, team_id)

    'Time humano acionado: dossiê registrado e conversa marcada como aguardando atendente. ' \
      'Na SUA resposta, avise o cliente que uma pessoa do time vai assumir e CONTINUE atendendo ' \
      'normalmente até o atendente assumir de fato.'
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Failed to handoff conversation'
  end

  private

  # Modelo A (decisão Paulo 12/06): a IA NÃO solta a conversa no handoff — segura o
  # cliente até um humano PUXAR a atribuição ("Assumir conversa"), que é a única prova
  # real de presença (online ≠ disponível; atribuído ≠ presente). Sem round-robin:
  # atribuição automática a um ausente esconderia a conversa da fila coletiva do time.
  # A espera fica filtrável via custom attribute `aguardando_humano_desde`; o concern
  # limpa quando um humano assume (atribuição), responde (A2c) ou a conversa resolve.
  #
  # F1.1 (modo FILA, reply_assignment_gate ON): a IA SOLTA o espelho ANTES do
  # bot_handoff! (assignee_agent_bot_id = nil), mantendo o team_id. A conversa fica
  # "open, sem dono, com time" = aguardando humano numa fila por time. O gate da
  # re-captura (F1.2) impede a IA de pegar a conversa de volta na próxima mensagem.
  # Modo Clássico (flag OFF): comportamento Modelo A intacto (espelho mantido).
  def trigger_handoff(conversation, reason, team_id = nil)
    fila_mode = conversation.account.reply_assignment_gate_enabled?
    create_handoff_note(conversation, reason) if reason.present?

    # F1.1: solta o espelho antes do handoff quando no modo fila. No modo fila a conversa
    # vira "open, sem dono, com time" — o round-robin NÃO pode empurrá-la pra um agente
    # (pull, não push), então desligamos o auto-assign nesta conversa durante o handoff.
    if fila_mode
      conversation.skip_auto_assignment = true
      release_captain_mirror(conversation)
    end

    # Trigger the bot handoff (sets status to open + dispatches events)
    conversation.bot_handoff!

    # Time + marcador no MESMO save. No modo Clássico, com o espelho mantido, o A2b impede
    # o auto-assign de time (assignee_agent_bot presente). No modo fila, skip_auto_assignment
    # garante que a conversa fique na fila do time, sem dono.
    team = resolve_team(conversation, team_id)
    attrs = (conversation.custom_attributes || {}).merge('aguardando_humano_desde' => Time.current.iso8601)
    update_attrs = { custom_attributes: attrs }
    update_attrs[:team] = team if team
    conversation.update!(update_attrs)

    # Send out of office message if applicable (since template messages were suppressed while Captain was handling)
    send_out_of_office_message_if_applicable(conversation)
  end

  # F1.1: solta o espelho captain (não toca em time/dono humano). Idempotente — só age
  # se a IA ainda é a dona. Mantém o team_id pra a conversa cair na fila do time certo.
  def release_captain_mirror(conversation)
    return unless conversation.assignee_agent_bot&.captain?

    conversation.update!(assignee_agent_bot_id: nil)
  end

  # post the reason as a private note (dossiê pro humano que assumir)
  def create_handoff_note(conversation, reason)
    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: @assistant,
      account: conversation.account,
      inbox: conversation.inbox,
      content: reason
    )
  end

  # LLM pode alucinar id — validar SEMPRE na conta.
  def resolve_team(conversation, team_id)
    return nil if team_id.blank?

    conversation.account.teams.find_by(id: team_id)
  end

  def send_out_of_office_message_if_applicable(conversation)
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
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
