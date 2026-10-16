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
  def assign_ai_agent(assistant_ids) # rubocop:disable Metrics/CyclomaticComplexity
    return if assistant_ids.blank?
    # F1.4 (modo FILA): a re-triagem de órfãs não reanexa a IA (senão a fila some). A triagem
    # inicial nunca seta esta flag — só o OrphanRetriageJob no modo fila.
    return if Current.skip_ai_agent_assignment
    # A IA é a porta de entrada TAMBÉM na reentrada: cliente que volta depois de um
    # atendimento humano encerrado pode estar agradecendo (nada a fazer), trazendo assunto
    # novo (triar) ou dando sequência ao caso de antes (devolver pro time/pessoa que cuidava).
    # Quem separa os três é ela — sem isso, toda reentrada cai na fila geral e é distribuída
    # na mão. O contexto de quem atendeu antes vai pro agente em HumanHistoryNote.
    #
    # O que ela NÃO faz é tomar conversa que está NA MÃO de alguém: com assignee humano
    # presente o dono é ele, e a IA não entra (senão a conversa some da fila do atendente).
    # A exceção é opt-in por conta: a conversa que o CLIENTE reabriu (ver abaixo).
    return if human_owner_keeps_conversation?

    # Procedência (opt-in por conta): se a conversa nasceu de uma resposta a um template que um
    # HUMANO mandou 1:1 pro contato (<24h), o dono é esse humano -> a IA não assume. Cobre o caso
    # do incidente 22/07, em que o template saiu de OUTRA conversa/ficha do mesmo contato — a
    # checagem de assignee, que só olha ESTA conversa, não pegaria.
    return if reassigned_to_human_template_sender?

    assistant = eligible_captain_assistant(assistant_ids.first) # params chegam como ARRAY
    return if assistant.nil?

    mirror = assistant.mirror_agent_bot # cria o espelho se faltar (Fase A)
    return if mirror.nil?

    # MESMO save: limpa humano + seta espelho (invariante; saves separados quebram com
    # allow_auto_assign). O after_commit da Fase A enfileira AssignmentKickJob.
    # nil = o service recusou (ex.: trava de teste do assistant, etiqueta sem IA da conta) ->
    # a IA não vira dona da regra.
    assigned = Conversations::AssignmentService.new(
      conversation: @conversation, assignee_id: mirror.id, assignee_type: 'AgentBot'
    ).perform
    return if assigned.nil?

    # A partir daqui a IA é a "dona" da triagem: as ações seguintes da MESMA regra
    # (ex.: assign_team → "Atribuído a recepção por Clara") são atribuídas a ela, não
    # ao genérico "Sistema de Automação". O ActionService não reseta Current.executed_by
    # entre ações, e assign_ai_agent roda ANTES de assign_team (ordem segura A2b).
    Current.executed_by = assistant
  end

  # Reabertura pelo cliente (opt-in `ia_assume_reaberta`): a conversa estava resolvida, o cliente
  # escreveu e o sistema reabriu. O atendente que ficou atribuído já tinha encerrado o caso; deixá-la
  # com ele era o que fazia a equipe desatribuir na mão e a conversa se perder na fila geral (Tozi,
  # 15/10). A IA assume e decide pelo HumanHistoryNote se devolve ao dono anterior ou faz a triagem.
  #
  # Reabertura feita pelo ATENDENTE fica com ele (decisão do Paulo em 16/10). A distinção sai do
  # que existe no ciclo desde a última resolução, porque o evento chega igual nos dois casos (sem
  # performed_by): humano falou no ciclo -> é dele; ninguém do cliente falou -> foi o atendente
  # que reabriu na mão. A resposta da pesquisa de NPS não reabre a conversa, então não conta.
  #
  # Só no gatilho `conversation_opened`: em `message_created`, o mesmo estado (cliente falou,
  # humano ainda não) persiste depois que a IA devolveu a conversa ao atendente, e ela a tomaria
  # de volta a cada mensagem.
  def human_owner_keeps_conversation?
    @conversation.assignee_id.present? && !customer_reopened_after_resolution?
  end

  def customer_reopened_after_resolution?
    return false unless @account.ia_assume_reaberta_enabled?
    return false unless @trigger_event == 'conversation_opened'

    resolved_at = ReportingEvent.where(conversation_id: @conversation.id, name: 'conversation_resolved').maximum(:event_end_time)
    return false if resolved_at.nil?

    cycle = @conversation.all_messages.where(private: false).where('created_at > ?', resolved_at)
    return false if cycle.exists?(message_type: :outgoing, sender_type: 'User')

    since = [resolved_at, @conversation.nps_responses.maximum(:answered_at)].compact.max
    cycle.where(message_type: :incoming).exists?(['created_at > ?', since])
  end

  # Assistant existente E elegível (C8 no caminho in-process): a IA só atua em inbox onde está
  # registrada. nil em qualquer caso inválido -> assign_ai_agent para.
  def eligible_captain_assistant(assistant_id)
    assistant = @account.captain_assistants.find_by(id: assistant_id)
    return nil if assistant.nil?
    return nil unless @conversation.inbox.captain_assistants.exists?(assistant.id)

    assistant
  end

  # Procedência da triagem (OPT-IN por conta, default OFF via custom_attribute):
  # quando a conversa nasce de uma resposta a um template que um HUMANO mandou 1:1 pro contato
  # (última msg outgoing de template <24h com sender User), o dono é esse humano — a IA não
  # assume. Template de CAMPANHA/disparo (MessageBuilder sem user -> sem sender User) e openers
  # de IA seguem pra triagem normal. Determinístico, sem LLM. Retorna true quando reatribuiu ao
  # humano (aí assign_ai_agent para). Guarda desligada => comportamento idêntico ao atual.
  def reassigned_to_human_template_sender?
    return false unless @account.custom_attributes&.dig('ai_triage_respects_human_template')

    sender = human_template_sender_for_contact
    return false if sender.nil?

    Conversations::AssignmentService.new(conversation: @conversation, assignee_id: sender.id).perform
    assign_conversation_team(sender)
    true
  end

  # User remetente da última mensagem outgoing de TEMPLATE pro contato nas últimas 24h — só
  # quando foi um humano 1:1 (sender User). Busca nas conversas do MESMO contato na mesma inbox
  # (o template pode ter saído de outra conversa/ficha do contato — foi o caso do incidente).
  def human_template_sender_for_contact
    contact_id = @conversation.contact_id
    return nil if contact_id.blank?

    latest_template = Message.joins(:conversation)
                             .where(conversations: { account_id: @account.id, contact_id: contact_id, inbox_id: @conversation.inbox_id })
                             .where(message_type: %i[outgoing template])
                             .where('messages.created_at > ?', 24.hours.ago)
                             .where("messages.additional_attributes -> 'template_params' IS NOT NULL")
                             .order('messages.created_at DESC')
                             .first
    return nil unless latest_template&.sender_type == 'User'

    latest_template.sender
  end

  # "Time dele se houver": só quando não-ambíguo (o humano pertence a exatamente 1 time) e a
  # conversa ainda não tem time — evita a dessincronização assignee∉team (bug do 403).
  def assign_conversation_team(user)
    return if @conversation.team_id.present?

    teams = user.teams.where(account_id: @account.id)
    return unless teams.count == 1

    @conversation.update!(team_id: teams.first.id)
  end
end
