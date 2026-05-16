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
    return false if skip_labels?
    return false if skip_groups?
    return false if skip_agent_bot?

    true
  end

  private

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
