module Enterprise::MessageTemplates::HookExecutionService
  MAX_ATTACHMENT_WAIT_SECONDS = 4

  def trigger_templates
    super
    return unless should_process_captain_response?
    return perform_handoff unless inbox.captain_active?

    process_captain_behavior(inbox.captain_assistant)
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

  def schedule_or_debounce(assistant)
    trigger_immediate_typing # "digitando..." na hora, ja cobrindo o tempo do debounce
    debounce = assistant.behavior['debounce_seconds'].to_i
    if debounce.positive?
      Captain::Behavior::DebounceService.new(assistant: assistant, conversation: conversation).schedule
    else
      schedule_captain_response
    end
  end

  # Mostra "digitando..." pro cliente assim que a mensagem passa no router, antes
  # mesmo do debounce — best-effort (so WhatsApp Cloud responde de fato).
  def trigger_immediate_typing
    source_id = message.try(:source_id)
    return if source_id.blank?

    inbox.channel.try(:send_typing_indicator, source_id)
  rescue StandardError => e
    Rails.logger.warn("[Captain] typing inicial falhou: #{e.message}")
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

  def schedule_captain_response
    job_args = [conversation, conversation.inbox.captain_assistant]

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

  def should_process_captain_response?
    # Responde em pending E em open: depois do handoff/atribuição o bot continua
    # atendendo até um humano de fato responder (skip_after_human_response no
    # RouterService corta quando um atendente envia mensagem). Evita deixar o
    # cliente sem resposta quando não há humano disponível na hora.
    (conversation.pending? || conversation.open?) && message.incoming? && inbox.captain_assistant.present? && !human_takeover_locked?
  end

  # Checkbox "Atendimento humano" no painel lateral: trava o bot pra o atendente assumir.
  def human_takeover_locked?
    [true, 'true', 1, '1'].include?(conversation.custom_attributes&.dig('atendimento_humano'))
  end

  def perform_handoff
    return unless conversation.pending?

    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{conversation.id}")
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account.id,
      inbox_id: conversation.inbox.id,
      content: 'Transferring to another agent for further assistance.'
    )
    conversation.bot_handoff!
    send_out_of_office_message_after_handoff
  end

  def send_out_of_office_message_after_handoff
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  def captain_handling_conversation?
    (conversation.pending? || conversation.open?) && inbox.respond_to?(:captain_assistant) && inbox.captain_assistant.present?
  end
end
