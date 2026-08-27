class Captain::Tools::Copilot::ChangePriorityService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'change_priority'
  end
  description 'Change the priority of a conversation (none, low, medium, high, urgent)'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :priority, type: :string, desc: 'New priority: none, low, medium, high, or urgent', required: true

  def execute(conversation_id:, priority:)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?

    if priority == 'none'
      conversation.update!(priority: nil)
    else
      return "Invalid priority: #{priority}" unless Conversation.priorities.key?(priority)

      conversation.update!(priority: priority)
    end

    "Conversation ##{conversation_id} priority changed to #{priority}"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
