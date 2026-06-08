class Captain::Tools::Copilot::ResolveConversationService < Captain::Tools::BaseTool
  def self.name
    'resolve_conversation'
  end
  description 'Resolve a conversation (triggers CSAT survey and other side effects)'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true

  def execute(conversation_id:)
    conversation = @assistant.account.conversations.find_by(display_id: conversation_id)
    return 'Conversation not found' if conversation.blank?
    return 'Conversation is already resolved' if conversation.resolved?

    conversation.resolved!
    "Conversation ##{conversation_id} resolved"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
