class LlmFormatter::ConversationLlmFormatter < LlmFormatter::DefaultLlmFormatter
  def format(config = {})
    sections = build_header_sections(config)
    sections.concat(build_metadata_sections)

    attributes = build_attributes
    if attributes.present?
      sections << 'Conversation Attributes:'
      sections << attributes
    end

    sections.join("\n")
  end

  private

  def build_header_sections(config)
    sections = []
    sections << "Conversation ID: ##{@record.display_id}"
    sections << "Channel: #{@record.inbox.channel.name}"
    sections << 'Message History:'
    sections << (@record.messages.any? ? build_messages(config) : 'No messages in this conversation')
    sections << "Contact Details: #{@record.contact.to_llm_text}" if config[:include_contact_details]
    sections
  end

  def build_metadata_sections
    [
      "Assignee: #{field_or_default(@record.assignee&.name, 'unassigned')}",
      "Team: #{field_or_default(@record.team&.name)}",
      "Labels: #{field_or_default(@record.label_list.join(', ').presence)}",
      "Status: #{@record.status}",
      "Priority: #{field_or_default(@record.priority)}",
      "Created: #{@record.created_at.strftime('%Y-%m-%d %H:%M')}"
    ]
  end

  def field_or_default(value, fallback = 'none')
    value.presence || fallback
  end

  def build_messages(config = {})
    return "No messages in this conversation\n" if @record.messages.empty?

    messages = @record.messages.where.not(message_type: [:activity, :template])

    if config[:token_limit]
      build_limited_messages(messages, config)
    else
      build_all_messages(messages, config)
    end
  end

  def build_all_messages(messages, config)
    message_text = ''
    messages.order(created_at: :asc).each do |message|
      # Skip private messages unless explicitly included in config
      next if message.private? && !config[:include_private_messages]

      message_text << format_message(message)
    end
    message_text
  end

  def build_limited_messages(messages, config)
    selected = []
    character_count = 0

    messages.reorder(created_at: :desc).each do |message|
      # Skip private messages unless explicitly included in config
      next if message.private? && !config[:include_private_messages]

      formatted = format_message(message)
      break if character_count + formatted.length > config[:token_limit]

      selected.prepend(formatted)
      character_count += formatted.length
    end

    selected.join
  end

  def format_message(message)
    sender = case message.sender_type
             when 'User'
               'Support Agent'
             when 'Contact'
               'User'
             else
               'Bot'
             end
    sender = "[Private Note] #{sender}" if message.private?
    "#{sender}: #{message.content_for_llm}\n"
  end

  def build_attributes
    attributes = @record.account.custom_attribute_definitions.with_attribute_model('conversation_attribute').map do |attribute|
      "#{attribute.attribute_display_name}: #{@record.custom_attributes[attribute.attribute_key]}"
    end
    attributes.join("\n")
  end
end
