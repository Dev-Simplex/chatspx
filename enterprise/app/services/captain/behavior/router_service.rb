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

  # Para números brasileiros (DDI 55), gera as duas formas — com o "9 a mais" do
  # celular e sem — para que a comparação seja robusta a como o WAHA, o operador
  # ou o usuário tenham digitado o número.
  def phone_variations(value)
    digits = value.to_s.gsub(/\D/, '')
    return [digits] if digits.blank?
    return [digits] unless digits.start_with?('55') && [12, 13].include?(digits.length)

    prefix = digits[0, 4] # "55" + DDD
    rest = digits[4..]    # "996247866" (com 9) ou "96247866" (sem 9)
    return [digits] if rest.blank?

    with_9 = rest.start_with?('9') && rest.length == 9 ? digits : "#{prefix}9#{rest}"
    without_9 = rest.start_with?('9') && rest.length == 9 ? "#{prefix}#{rest[1..]}" : digits
    [with_9, without_9].uniq
  end

  def skip_labels?
    skip_labels = @config['skip_labels']
    return false if skip_labels.blank?

    Array(skip_labels).intersect?(@conversation.label_list)
  end

  def skip_groups?
    @config['skip_groups'] && @conversation.additional_attributes&.dig('type') == 'group'
  end

  def skip_agent_bot?
    @config['skip_agent_bot'] && @conversation.agent_bot_id.present?
  end
end
