module Enterprise::MessageTemplates::HookExecutionService # rubocop:disable Metrics/ModuleLength
  MAX_ATTACHMENT_WAIT_SECONDS = 4

  def trigger_templates
    super
    # D-12: pós-handoff sem humano disponível (fora do horário / ninguém online), o cliente
    # continua falando numa conversa órfã. A IA de TRIAGEM (Clara) reentra via kick (A2d) —
    # silêncio é pior que a especialista segurar o cliente. Humano que assumir cala ela.
    # Cobre também conversa resolvida que reabre quando o contato volta (A2e solta o dono).
    return reattach_triage_assistant if orphan_captain_reentry?

    return unless should_process_captain_response?
    return perform_handoff unless captain_quota_available?

    process_captain_behavior(assigned_assistant)
  end

  def should_send_greeting?
    return false if captain_handling_conversation?

    super
  end

  def should_send_out_of_office_message?
    return false if captain_handling_conversation?

    super
  end

  def should_send_email_collect?
    return false if captain_handling_conversation?

    super
  end

  private

  def process_captain_behavior(assistant)
    return trigger_copilot_if_applicable(assistant) if message.private?
    return log_and_skip(assistant, 'router_skip') unless router_allows?(assistant)

    # Conversa que a IA vai atender fica VISÍVEL na fila (open), em vez de escondida
    # em pending. Ruído (grupos/status/qualquer router_skip) não chega aqui e segue
    # pending. O Captain responde em open normalmente (should_process_captain_response?).
    ensure_conversation_open(assistant)

    return log_and_skip(assistant, 'business_hours_skip') if outside_hours_ignore?(assistant)

    schedule_or_debounce(assistant)
  end

  def router_allows?(assistant)
    Captain::Behavior::RouterService.new(assistant: assistant, conversation: conversation, message: message).should_respond?
  end

  def outside_hours_ignore?(assistant)
    status = Captain::Behavior::BusinessHoursChecker.new(assistant: assistant).status
    status == :outside && assistant.behavior.dig('business_hours', 'outside_hours_action') == 'ignore'
  end

  # Tira a conversa do limbo "pending" assim que a IA assume (passou o router),
  # deixando-a visível na fila de Abertas. Atribui a ação ao assistant via
  # Current.executed_by pra a atividade sair como "<Clara>" (e não como o usuário
  # do token da ponte WAHA). Best-effort: nunca derruba o fluxo de mensagem.
  def ensure_conversation_open(assistant)
    return unless conversation.pending?

    previous_executed_by = Current.executed_by
    Current.executed_by = assistant
    begin
      conversation.open!
    rescue StandardError => e
      Rails.logger.warn("[Captain] auto-open conv=#{conversation.id}: #{e.message}")
    ensure
      Current.executed_by = previous_executed_by
    end
  end

  def schedule_or_debounce(assistant)
    mark_customer_message_read # tique azul (lido) na hora, SEM "digitando" continuo
    debounce = assistant.behavior['debounce_seconds'].to_i
    if debounce.positive?
      Captain::Behavior::DebounceService.new(assistant: assistant, conversation: conversation).schedule
    else
      schedule_captain_response(assistant)
    end
  end

  # Marca a mensagem do cliente como lida assim que passa no router (best-effort,
  # so WhatsApp Cloud). NAO mostra "digitando" continuo — isso fica pras rajadas
  # curtas antes de cada resposta (mais natural).
  def mark_customer_message_read
    source_id = message.try(:source_id)
    return if source_id.blank?

    inbox.channel.try(:send_typing_indicator, source_id, false)
  rescue StandardError => e
    Rails.logger.warn("[Captain] read receipt falhou: #{e.message}")
  end

  def log_and_skip(assistant, event_type)
    Captain::AssistantLog.create!(captain_assistant: assistant, conversation: conversation,
                                  message_id: message.id, event_type: event_type)
  end

  def trigger_copilot_if_applicable(assistant)
    service = Captain::Behavior::CopilotTriggerService.new(assistant: assistant, message: message, conversation: conversation)
    return unless service.should_trigger?

    Captain::AssistantLog.create!(captain_assistant: assistant, conversation: conversation,
                                  message_id: message.id, event_type: 'copilot_trigger')
    service.trigger
  end

  # O job recebe o assistant que o gate resolveu pela CONVERSA — fim do re-derive
  # via inbox (o dono pode ser qualquer IA elegível, não "a IA da inbox").
  def schedule_captain_response(assistant)
    job_args = [conversation, assistant]

    if message.attachments.blank?
      Captain::Conversation::ResponseBuilderJob.perform_later(*job_args)
    else
      wait_time = calculate_attachment_wait_time
      Captain::Conversation::ResponseBuilderJob.set(wait: wait_time).perform_later(*job_args)
    end
  end

  def calculate_attachment_wait_time
    attachment_count = message.attachments.size
    base_wait = 1.second

    # Wait longer for more attachments or larger files
    additional_wait = [attachment_count * 1, MAX_ATTACHMENT_WAIT_SECONDS].min.seconds
    base_wait + additional_wait
  end

  # Gate por ATRIBUIÇÃO (D-6): a IA só processa conversa cujo dono é o espelho dela.
  # pending aceito durante a transição (legado); open é o estado normal do modelo novo.
  def should_process_captain_response?
    (conversation.pending? || conversation.open?) && message.incoming? && assigned_assistant.present?
  end

  def assigned_assistant
    return @assigned_assistant if defined?(@assigned_assistant)

    mirror = conversation.assignee_agent_bot
    @assigned_assistant = (mirror.captain_assistant if mirror&.captain?)
  end

  # D-12: reentrada da IA do setor em conversa órfã (sem humano E sem IA).
  #
  # F1.2 🔴 (modo FILA, reply_assignment_gate ON): a re-captura automática está DESLIGADA.
  # No modo fila, a IA solta a conversa numa fila por time no handoff (F1.1) e ela deve
  # PERMANECER aguardando humano — a próxima mensagem do cliente NÃO pode fazer a IA do
  # setor pegar a conversa de volta (senão a fila nunca existe). Modo Clássico (flag OFF):
  # comportamento D-12 intacto (a IA do setor reentra pra não deixar o cliente no silêncio).
  def orphan_captain_reentry?
    return false unless captain_reentry_allowed?

    message.incoming? && !message.private? && conversation.open? &&
      conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil? &&
      triage_assistant.present?
  end

  def captain_reentry_allowed?
    return true unless conversation.account.reply_assignment_gate_enabled?

    Captain::Conversation::SessionResetService.pending_reentry?(conversation)
  end

  def reattach_triage_assistant
    mirror = AgentBot.captain.find_by(captain_assistant_id: triage_assistant.id)
    return if mirror.nil?

    # Reaberta volta pra TRIAGEM (Clara), com o time LIMPO: ela lê o histórico + a mensagem
    # nova e decide se continua o assunto anterior ou abre um novo, e roteia. Dispara o kick (A2d).
    attrs = (conversation.custom_attributes || {}).except('captain_session_pending_reentry')
    conversation.update!(assignee_agent_bot_id: mirror.id, team_id: nil, custom_attributes: attrs)
  rescue StandardError => e
    Rails.logger.warn("[Captain] reentrada conv=#{conversation.id}: #{e.message}")
  end

  # O agente de TRIAGEM da conta (config['triage']=true, ex: Clara/recepção), se ELEGÍVEL na
  # inbox. É pra ele que a reentrada manda — não pro especialista do último time, porque o
  # cliente pode ter voltado por OUTRO assunto; a triagem reavalia.
  def triage_assistant
    return @triage_assistant if defined?(@triage_assistant)

    @triage_assistant = resolve_triage_assistant
  end

  def resolve_triage_assistant
    assistant = Captain::Assistant.where(account_id: conversation.account_id)
                                  .detect { |a| a.config['triage'] == true }
    return nil if assistant.nil?
    return nil unless ::CaptainInbox.exists?(inbox_id: inbox.id, captain_assistant_id: assistant.id)

    assistant
  end

  # Quota re-keyada: não depende mais de inbox.captain_active? (que morre keyado por inbox).
  def captain_quota_available?
    conversation.account.usage_limits[:captain][:responses][:current_available].positive?
  end

  def perform_handoff
    assistant = assigned_assistant
    return if assistant.blank? # re-keyado: só age quando uma IA é dona da conversa

    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{conversation.id}")
    create_handoff_message(assistant)
    # IA solta a conversa: o gate para de bater aqui (sem spam) e a conversa fica
    # sem dono -> visível como órfã (vigia D-12 / tab condicional na Fase C).
    conversation.update!(assignee_agent_bot_id: nil)
    conversation.bot_handoff!
    send_out_of_office_message_after_handoff
  end

  def create_handoff_message(assistant)
    I18n.with_locale(conversation.account.locale) do
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account.id,
        inbox_id: conversation.inbox.id,
        sender: assistant, # bolha com identidade da IA (antes saía sem sender)
        content: assistant.config['handoff_message'].presence || I18n.t('conversations.captain.handoff')
      )
    end
  end

  def send_out_of_office_message_after_handoff
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  # Supressão de greeting/OOO/email_collect por ELEGIBILIDADE (inbox tem IA) OU atribuição.
  # Por quê: a triagem atribui DEPOIS da criação — se a supressão fosse só por atribuição,
  # a conversa receberia greeting automático na janela entre criação e triagem (regressão
  # visível). Elegibilidade preserva o comportamento atual.
  def captain_handling_conversation?
    return false unless conversation.pending? || conversation.open?

    assigned_assistant.present? || ::CaptainInbox.exists?(inbox_id: inbox.id)
  end
end
