module Enterprise::ActionService
  def add_sla(sla_policy_id)
    return if sla_policy_id.blank?

    sla_policy = @account.sla_policies.find_by(id: sla_policy_id.first)
    return if sla_policy.nil?
    return if @conversation.sla_policy.present?

    Rails.logger.info "SLA:: Adding SLA #{sla_policy.id} to conversation: #{@conversation.id}"
    @conversation.update!(sla_policy_id: sla_policy.id)
  end

  # C5: triagem/macro atribuem a conversa ao espelho captain do assistant.
  # No-op silencioso em tudo inválido (padrão add_sla). Ordem segura: assign_ai_agent
  # ANTES de assign_team (guard A2b); a ordem inversa com team allow_auto_assign cria
  # um humano intermediário que a IA limpa em seguida — documentado, sem reordenação no v1.
  def assign_ai_agent(assistant_ids)
    return if assistant_ids.blank?
    # F1.4 (modo FILA): a re-triagem de órfãs não reanexa a IA (senão a fila some). A triagem
    # inicial nunca seta esta flag — só o OrphanRetriageJob no modo fila.
    return if Current.skip_ai_agent_assignment
    # Reopen de conversa cuja ÚLTIMA fala (humano×IA) foi de um HUMANO não acorda a IA:
    # o humano/time estava tratando, reabriu por resposta do cliente/NPS -> volta pro
    # humano, não pra IA roubar da mão dele. Triagem inicial não tem outgoing -> não barra.
    return if last_outgoing_by_human?

    assistant = @account.captain_assistants.find_by(id: assistant_ids.first) # params chegam como ARRAY
    return if assistant.nil?
    # Elegibilidade (C8 no caminho in-process): IA só atua em inbox onde está registrada
    return unless @conversation.inbox.captain_assistants.exists?(assistant.id)

    mirror = assistant.mirror_agent_bot # cria o espelho se faltar (Fase A)
    return if mirror.nil?

    # MESMO save: limpa humano + seta espelho (invariante; saves separados quebram com
    # allow_auto_assign). O after_commit da Fase A enfileira AssignmentKickJob.
    Conversations::AssignmentService.new(
      conversation: @conversation, assignee_id: mirror.id, assignee_type: 'AgentBot'
    ).perform

    # A partir daqui a IA é a "dona" da triagem: as ações seguintes da MESMA regra
    # (ex.: assign_team → "Atribuído a recepção por Clara") são atribuídas a ela, não
    # ao genérico "Sistema de Automação". O ActionService não reseta Current.executed_by
    # entre ações, e assign_ai_agent roda ANTES de assign_team (ordem segura A2b).
    Current.executed_by = assistant
  end

  # Última mensagem enviada por HUMANO×IA (ignora NPS/template/atividade): se o último
  # a falar foi um humano (User), a conversa estava na mão dele — a reentrada não deve
  # reatribuir pra IA. Sem nenhuma mensagem (triagem inicial) retorna false (não barra).
  def last_outgoing_by_human?
    last = @conversation.messages
                        .where(message_type: :outgoing)
                        .where(sender_type: %w[User Captain::Assistant])
                        .order(created_at: :desc)
                        .first
    last&.sender_type == 'User'
  end
end
