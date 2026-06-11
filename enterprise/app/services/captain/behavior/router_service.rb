class Captain::Behavior::RouterService
  def initialize(assistant:, conversation:, message:)
    @assistant = assistant
    @conversation = conversation
    @message = message
    @config = assistant.behavior['router'] || {}
  end

  # Só guards TÉCNICOS sobrevivem (D-6): activity, conteúdo vazio, grupos.
  # Guards de NEGÓCIO morreram com o gate por atribuição: whitelist de fones
  # (only_contact_phones), skip_labels, skip_agent_bot (bug latente: lia coluna
  # inexistente) e skip_after_human_response (papel assumido por: gate por
  # atribuição + callback de exclusividade reset_agent_bot_when_assignee_present
  # + A2c, que desatribui o espelho quando um humano responde SEM se atribuir).
  def should_respond?
    return false if @message.activity?
    return false if @message.content.blank? && @message.attachments.blank?
    return false if skip_groups?

    true
  end

  private

  # skip_groups continua honrando a config (comportamento preservado p/ grupos WAHA).
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
end
