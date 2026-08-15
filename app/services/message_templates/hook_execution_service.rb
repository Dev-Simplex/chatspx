class MessageTemplates::HookExecutionService
  pattr_initialize [:message!]

  def perform
    return if conversation.last_incoming_message.blank?
    return if message.auto_reply_email?

    trigger_templates
  end

  private

  delegate :inbox, :conversation, to: :message
  delegate :contact, to: :conversation

  def trigger_templates
    ::MessageTemplates::Template::OutOfOffice.new(conversation: conversation).perform if should_send_out_of_office_message?
    ::MessageTemplates::Template::Greeting.new(conversation: conversation).perform if should_send_greeting?
    ::MessageTemplates::Template::EmailCollect.new(conversation: conversation).perform if inbox.enable_email_collect && should_send_email_collect?
  end

  def should_send_out_of_office_message?
    return false unless out_of_office_context_allows?
    # should not send for outbound messages
    return false unless message.incoming?
    # prevents sending out-of-office message if an agent has sent a message in last 5 minutes
    # ensures better UX by not interrupting active conversations at the end of business hours
    return false if conversation.messages.outgoing.where(private: false).exists?(['created_at > ?', 5.minutes.ago])

    inbox.out_of_office? && conversation.messages.today.template.empty? && inbox.out_of_office_message.present?
  end

  # Contexto da conversa que veta o fora-de-horário antes de qualquer checagem de mensagem ou de
  # inbox: campanha (a própria campanha é a abordagem), tweet e GRUPO (ver #group_conversation?).
  def out_of_office_context_allows?
    return false if conversation.campaign.present?
    # should not send if its a tweet message
    return false if conversation.tweet?
    return false if group_conversation?

    true
  end

  def first_message_from_contact?
    conversation.messages.outgoing.count.zero? && conversation.messages.template.count.zero?
  end

  def should_send_greeting?
    return false if conversation.campaign.present?
    # should not send if its a tweet message
    return false if conversation.tweet?
    # Grupo de WhatsApp não recebe mensagem automática de entrada/saída — ver #group_conversation?.
    return false if group_conversation?

    first_message_from_contact? && inbox.greeting_enabled? && inbox.greeting_message.present?
  end

  # Conversa de GRUPO de WhatsApp não recebe greeting / fora-de-horário / coleta de e-mail.
  #
  # Por quê: essas mensagens são o "olá, como posso ajudar?" dirigido a UMA pessoa que acabou de
  # chamar. Num grupo de trabalho com N participantes elas viram ruído para todo mundo, e o
  # gatilho é a mensagem de QUALQUER integrante — o bot fala sozinho no meio da conversa alheia.
  # Não é hipótese: a conv 12 (grupo) recebeu o texto de fora-de-horário duas vezes no mesmo dia.
  #
  # A coleta de e-mail é redundante aqui (só roda em web widget, que nunca é grupo), mas o guard
  # fica uniforme de propósito: se outro canal ganhar semântica de grupo, não abre buraco novo.
  #
  # Ponto único de verdade: Conversation#group? (C1). Nunca reimplementar a heurística de @g.us.
  def group_conversation?
    conversation.group?
  end

  def email_collect_was_sent?
    conversation.messages.where(content_type: 'input_email').present?
  end

  # TODO: we should be able to reduce this logic once we have a toggle for email collect messages
  def should_send_email_collect?
    return false if conversation.campaign.present?
    # Grupo de WhatsApp não recebe mensagem automática de entrada/saída — ver #group_conversation?.
    return false if group_conversation?

    !contact_has_email? && inbox.web_widget? && !email_collect_was_sent?
  end

  def contact_has_email?
    contact.email
  end
end
MessageTemplates::HookExecutionService.prepend_mod_with('MessageTemplates::HookExecutionService')
