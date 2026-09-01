class Captain::Tools::Copilot::SendMessageService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'send_message'
  end
  description 'Send a message in a conversation (outgoing or private note)'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :content, type: :string, desc: 'Message content to send', required: true
  param :private, type: :boolean, desc: 'Send as private note instead of outgoing message (default: false)'

  def execute(conversation_id:, content:, private: false)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?

    params = { content: content, private: private }
    message = Messages::MessageBuilder.new(nil, conversation, params).perform
    type_label = private ? 'Private note' : 'Message'
    "#{type_label} sent in conversation ##{conversation_id} (message id: #{message.id})"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
