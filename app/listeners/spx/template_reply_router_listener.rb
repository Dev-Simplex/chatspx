# Roteia a RESPOSTA de um cliente a um template HSM: a resposta pertence a quem o
# template define, não a quem estava na conversa quando ele foi enviado.
#   - template MANUAL (sender User): a conversa vai pro humano que enviou o template
#     (ele puxou o cliente; a resposta é dele — mesmo que a conversa estivesse órfã
#     ou atribuída a outra pessoa)
#   - template de DISPARO/remarketing (sem sender + label de remarketing): vai pra IA
#     configurada, que lê o contexto e decide se o cliente fala do template ou de
#     outro assunto (cobre o buraco de conversa ABERTA com humano, onde nenhuma
#     automation de conversation_opened dispara)
# A resposta só é "ao template" enquanto o template for a última fala nossa: qualquer
# outgoing posterior (humano ou IA já atendendo) desarma o roteamento sozinho.
#
# Opt-in por conta via settings['template_reply_routing'] — no-op pra todo o resto.
# Handler rescue-wrapped: roda pra TODA conta no AsyncDispatcher e uma exceção aqui
# derrubaria os listeners seguintes do EventDispatcherJob (ver FunnelAutomationListener).
class Spx::TemplateReplyRouterListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming?
    return if message.private?

    conversation = message.conversation
    return if conversation.nil?

    config = account.settings&.dig('template_reply_routing') || {}
    # Sai antes de tocar o banco quando não há nada a fazer nesta conta: nem
    # roteamento por conta, nem conversa vinda de campanha (o listener roda pra
    # TODA conta em TODA mensagem — ver P1.2 no BACKLOG).
    return if !config['enabled'] && conversation.campaign_id.blank?

    template = last_outgoing_before(conversation, message)
    return unless template&.additional_attributes&.key?('template_params')

    # Dono do disparo tem precedência e é opt-in DA CAMPANHA (o campo preenchido),
    # não da conta — o roteamento por conta existe pras heurísticas abaixo.
    return if route_to_campaign_owner(conversation)
    return unless config['enabled']

    if template.sender_type == 'User'
      route_to_sender(conversation, template)
    elsif template.sender_id.nil? && rmkt_labeled?(conversation, config)
      route_to_assistant(conversation, account, config['rmkt_assistant_id'])
    end
  rescue StandardError => e
    Rails.logger.error("[Spx::TemplateReplyRouterListener] conv=#{conversation&.id}: #{e.message}")
  end

  private

  def last_outgoing_before(conversation, message)
    conversation.messages
                .where(message_type: :outgoing, private: false)
                .where(id: ...message.id)
                .reorder(id: :desc)
                .first
  end

  # Dono do disparo: a campanha define quem atende AS RESPOSTAS dela. Devolve true
  # quando assumiu o roteamento (impede as heurísticas de conta atropelarem).
  #
  # A atribuição acontece AQUI, na resposta — não no envio — e isso é o ponto:
  # o Chatwoot liga `conversation_assignment` de fábrica, mas NÃO liga
  # `assigned_conversation_new_message`. Atribuir no disparo notificaria o dono uma
  # vez por destinatário, tudo ANTES de qualquer lead responder, e depois ficaria
  # mudo justamente na resposta — que é o momento que importa. Atribuindo no reply,
  # é uma notificação por lead que de fato voltou.
  #
  # ⚠️ Só vale em inbox SEM IA: atribuir humano dispara o
  # `reset_agent_bot_when_assignee_present` e cala o agente. Campanha em inbox com
  # IA precisa designar sem atribuir (frente spx/rodizio) — não use este campo lá.
  def route_to_campaign_owner(conversation)
    owner_id = conversation.campaign&.dispatch_assignee_id
    return false if owner_id.blank?
    return true if conversation.assignee_id == owner_id

    Conversations::AssignmentService.new(
      conversation: conversation, assignee_id: owner_id, assignee_type: 'User'
    ).perform
    true
  end

  def route_to_sender(conversation, template)
    return if conversation.assignee_id == template.sender_id

    Conversations::AssignmentService.new(
      conversation: conversation, assignee_id: template.sender_id, assignee_type: 'User'
    ).perform
  end

  def rmkt_labeled?(conversation, config)
    prefix = config['rmkt_label_prefix'].to_s
    return false if prefix.blank?

    conversation.label_list.any? { |label| label.to_s.start_with?(prefix) }
  end

  def route_to_assistant(conversation, account, assistant_id)
    assistant = account.captain_assistants.find_by(id: assistant_id)
    return if assistant.nil?
    return if conversation.assignee_agent_bot&.captain_assistant_id == assistant.id

    mirror = assistant.mirror_agent_bot
    return if mirror.nil?

    # AssignmentService valida a elegibilidade do espelho à inbox e limpa o humano no
    # mesmo save; o after_commit da conversa enfileira o kick que faz a IA responder.
    Conversations::AssignmentService.new(
      conversation: conversation, assignee_id: mirror.id, assignee_type: 'AgentBot'
    ).perform
  end
end
