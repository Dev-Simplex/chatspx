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
    allowed = Array(@config['only_contact_phones']).compact_blank.map { |p| normalize_phone(p) }
    contact_phone = normalize_phone(@conversation.contact&.phone_number)
    contact_phone.present? && allowed.include?(contact_phone)
  end

  def normalize_phone(value)
    value.to_s.gsub(/\D/, '')
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
