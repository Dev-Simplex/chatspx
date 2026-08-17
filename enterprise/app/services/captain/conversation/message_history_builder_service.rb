class Captain::Conversation::MessageHistoryBuilderService
  RESOLUTION_MARKER = '<conversation_boundary status="resolved" />'.freeze

  def initialize(conversation:, assistant: nil, directive: nil)
    @conversation = conversation
    @assistant = assistant
    @directive = directive
  end

  def perform
    history = conversation_messages_for_context.filter_map do |message|
      message_hash = message_hash_for_context(message)
      next if message_hash.blank?

      agent_name = message.additional_attributes&.dig('agent_name')
      message_hash[:agent_name] = agent_name if forwardable_agent_name?(agent_name)
      message_hash
    end
    history << { content: @directive, role: 'user' } if @directive.present?
    history
  end

  private

  def conversation_messages_for_context
    @conversation.messages
                 .where(private: false, message_type: [:incoming, :outgoing, :activity])
                 .reorder(created_at: :asc, id: :asc)
                 .reject { |message| survey_message?(message) }
  end

  def message_hash_for_context(message)
    return activity_message_hash(message) if message.message_type == 'activity'

    content = if message.incoming?
                with_reply_context(message, prepare_multimodal_message_content(message))
              else
                message.content.presence || outgoing_attachment_placeholder(message)
              end

    {
      content: content,
      role: determine_role(message)
    }
  end

  def activity_message_hash(message)
    activity = message.content_attributes.to_h['activity'].to_h
    return unless activity['type'] == 'conversation_status_changed' && activity['status'] == 'resolved'

    {
      content: RESOLUTION_MARKER,
      role: 'assistant'
    }
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'user' : 'assistant'
  end

  def prepare_multimodal_message_content(message)
    Captain::OpenAiMessageBuilderService.new(message: message).generate_content
  end

  def survey_message?(message)
    return true if %w[input_csat input_nps].include?(message.content_type)

    message.content_attributes&.dig('nps_survey').present?
  end

  def outgoing_attachment_placeholder(message)
    message.attachments.any? ? '[attachment sent]' : ''
  end

  def with_reply_context(message, content)
    attrs = message.content_attributes || {}
    quoted = @conversation.messages.find_by(id: attrs['in_reply_to']) if attrs['in_reply_to'].present?
    quoted ||= @conversation.messages.find_by(source_id: attrs['in_reply_to_external_id']) if attrs['in_reply_to_external_id'].present?
    return content if quoted.nil?

    description = quoted_description(quoted)
    return content if description.blank?

    prefix = "[Replying to this previous message: \"#{description}\"] "
    content.is_a?(Array) ? [{ type: 'text', text: prefix }] + content : prefix + content.to_s
  end

  def quoted_description(message)
    text = message.content.to_s.gsub(/\s+/, ' ').strip
    return text[0, 180] if text.present?

    message.attachments.any? ? 'a previously sent attachment' : ''
  end

  def forwardable_agent_name?(agent_name)
    return false if agent_name.blank?
    return true if @assistant.nil?

    own_names = [@assistant.name.parameterize(separator: '_')] + @assistant.scenarios.enabled.map(&:handoff_key)
    own_names.include?(agent_name)
  end
end
