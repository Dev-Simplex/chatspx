class Captain::Tools::Copilot::ResolveConversationService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'resolve_conversation'
  end
  description 'Resolve a conversation (triggers CSAT survey and other side effects)'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true

  def execute(conversation_id:)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?
    return 'Conversation is already resolved' if conversation.resolved?

    conversation.resolved!
    "Conversation ##{conversation_id} resolved"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
