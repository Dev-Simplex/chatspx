class Captain::Behavior::CopilotTriggerService
  def initialize(assistant:, message:, conversation:)
    @assistant = assistant
    @message = message
    @conversation = conversation
    @config = assistant.behavior['copilot_trigger'] || {}
  end

  def should_trigger?
    return false unless @config['enabled']
    return false unless @message.private?

    hashtag = @config['hashtag'] || '#copilot'
    @message.content&.include?(hashtag)
  end

  def trigger
    config = {
      conversation_id: @conversation.display_id,
      previous_history: []
    }
    service = Captain::Copilot::ChatService.new(@assistant, config)
    service.generate_response(@message.content)
  end
end
