class Captain::Behavior::RouterService
  def initialize(assistant:, conversation:, message:)
    @assistant = assistant
    @conversation = conversation
    @message = message
    @config = assistant.behavior['router'] || {}
  end

  def should_respond?
    return false if @message.activity?
    return false if @message.content.blank? && @message.attachments.blank?
    return false if only_contact_phones_active? && !contact_phone_allowed?
    return false if skip_labels?
    return false if skip_groups?
    return false if skip_agent_bot?
    return false if skip_after_human_response?

    true
  end

  private

  def only_contact_phones_active?
    Array(@config['only_contact_phones']).any?(&:present?)
  end

  def contact_phone_allowed?
    allowed_variations = Array(@config['only_contact_phones']).compact_blank.flat_map { |p| phone_variations(p) }.uniq
    contact_variations = candidate_contact_phones.flat_map { |p| phone_variations(p) }.uniq
    contact_variations.intersect?(allowed_variations)
  end

  # Telefones a tentar match: contact.phone_number e o JID puro do WAHA (sem @c.us)
  # se a inbox for WAHA. O JID canônico não tem o "9 a mais" do celular brasileiro,
  # enquanto phone_number pode ter — então olhamos os dois.
  def candidate_contact_phones
    contact = @conversation.contact
    return [] unless contact
    jid = contact.custom_attributes&.dig('waha_whatsapp_jid').to_s.split('@').first
    [contact.phone_number, jid].compact_blank
  end

  # Para números brasileiros gera variações cobrindo: com/sem DDI 55, com/sem o
  # "9 a mais" do celular pós-2012. Cobre o WAHA (que historicamente persiste
  # JID sem o 9), o phone_number do contato (que o WAHA já tenha normalizado pro
  # formato novo), e operadores digitando à mão sem DDI.
  def phone_variations(value)
    digits = value.to_s.gsub(/\D/, '')
    return [digits] if digits.blank?

    br_with_ddi = digits.start_with?('55') && [12, 13].include?(digits.length)
    br_no_ddi   = !digits.start_with?('55') && [10, 11].include?(digits.length)
    return [digits] unless br_with_ddi || br_no_ddi

    with_ddi = br_with_ddi ? digits : "55#{digits}"
    prefix = with_ddi[0, 4] # "55" + DDD
    rest = with_ddi[4..]    # número local (8 ou 9 dígitos)
    return [digits] if rest.blank?

    with_9 = rest.start_with?('9') && rest.length == 9 ? with_ddi : "#{prefix}9#{rest}"
    without_9 = rest.start_with?('9') && rest.length == 9 ? "#{prefix}#{rest[1..]}" : with_ddi
    [with_ddi, with_9, without_9].uniq
  end

  def skip_labels?
    skip_labels = @config['skip_labels']
    return false if skip_labels.blank?

    Array(skip_labels).intersect?(@conversation.label_list)
  end

  def skip_groups?
    return false unless @config['skip_groups']

    conversation_is_group?
  end

  # WAHA não seta `additional_attributes['type'] = 'group'` que é o sinal padrão
  # do Chatwoot — em vez disso, o JID/chat_id do contato termina com `@g.us`.
  # Para cobrir os dois fluxos e qualquer integração futura, olhamos múltiplos
  # campos antes de decidir.
  def conversation_is_group?
    return true if @conversation.additional_attributes&.dig('type') == 'group'

    contact = @conversation.contact
    return false unless contact

    return true if contact.identifier.to_s.end_with?('@g.us')

    custom = contact.custom_attributes || {}
    return true if custom['waha_whatsapp_chat_id'].to_s.end_with?('@g.us')
    return true if custom['waha_whatsapp_jid'].to_s.end_with?('@g.us')

    false
  end

  def skip_agent_bot?
    @config['skip_agent_bot'] && @conversation.agent_bot_id.present?
  end

  # Quando a última mensagem outgoing pública (não-privada, não-template, não-NPS) foi
  # enviada por um User (humano), assume que o atendimento foi assumido manualmente
  # e Captain para de responder. Mensagens enviadas pelo próprio assistant (AgentBot)
  # NÃO contam — assim Clara pode responder múltiplas vezes em sequência sem se silenciar.
  def skip_after_human_response?
    return false unless @config['skip_after_human_response']

    last_outgoing = @conversation.messages
                                 .where(message_type: :outgoing, private: false)
                                 .where.not(id: @message.id)
                                 .order(created_at: :desc)
                                 .limit(5)
                                 .find { |m| !m.content_attributes&.dig('nps_survey') }
    return false unless last_outgoing

    last_outgoing.sender.is_a?(User)
  end
end
