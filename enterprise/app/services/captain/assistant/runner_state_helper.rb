module Captain::Assistant::RunnerStateHelper
  CONVERSATION_STATE_ATTRIBUTES = %i[
    id display_id inbox_id contact_id status priority
    label_list custom_attributes additional_attributes
  ].freeze

  CONTACT_STATE_ATTRIBUTES = %i[
    id name email phone_number identifier contact_type
    custom_attributes additional_attributes
  ].freeze

  CONTACT_INBOX_STATE_ATTRIBUTES = %i[id hmac_verified].freeze

  # Bloco 1.20, asserção (5): `referer_raw` é o dado CRU do visitante — a URL que nem escapando
  # virou http(s). Existe para diagnóstico. O snippet `prompts/snippets/conversation.liquid` itera
  # `additional_attributes` inteiro dentro do system prompt, então sem este filtro o valor cru
  # entraria literalmente no prompt da IA.
  BLOCKED_ADDITIONAL_ATTRIBUTES = %w[referer_raw].freeze

  CAMPAIGN_STATE_ATTRIBUTES = %i[id title message campaign_type description].freeze

  private

  def build_state
    state = {
      account_id: @assistant.account_id,
      assistant_id: @assistant.id,
      assistant_config: @assistant.config,
      timezone: @conversation&.inbox&.timezone.presence || 'UTC'
    }
    state[:source] = @source if @source.present?

    build_conversation_state(state) if @conversation
    state
  end

  def build_conversation_state(state)
    state[:conversation] = slice_attrs(@conversation, CONVERSATION_STATE_ATTRIBUTES)
    # Keep the handoff-wait marker in persistence for routing and filters, but do
    # not bias the assistant toward silence when the customer asks something new.
    state[:conversation][:custom_attributes] =
      (state[:conversation][:custom_attributes] || {}).except('aguardando_humano_desde')
    state[:channel_type] = @conversation.inbox&.channel_type
    state[:contact] = slice_attrs(@conversation.contact, CONTACT_STATE_ATTRIBUTES) if @conversation.contact
    state[:campaign] = slice_attrs(@conversation.campaign, CAMPAIGN_STATE_ATTRIBUTES) if @conversation.campaign
    state[:contact_inbox] = slice_attrs(@conversation.contact_inbox, CONTACT_INBOX_STATE_ATTRIBUTES) if @conversation.contact_inbox
  end

  def slice_attrs(record, keys)
    attrs = record.attributes.symbolize_keys.slice(*keys)
    return attrs unless attrs[:additional_attributes].is_a?(Hash)

    attrs.merge(additional_attributes: attrs[:additional_attributes].except(*BLOCKED_ADDITIONAL_ATTRIBUTES))
  end
end
