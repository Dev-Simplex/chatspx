class Captain::Tools::Copilot::TransferToInboxService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'transfer_to_inbox'
  end
  description 'Transfer a conversation to a different inbox'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :inbox_id, type: :integer, desc: 'ID of the target inbox', required: true

  def execute(conversation_id:, inbox_id:)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?

    inbox = @assistant.account.inboxes.find_by(id: inbox_id)
    return 'Inbox not found' if inbox.blank?

    conversation.update!(inbox_id: inbox.id)
    "Conversation ##{conversation_id} transferred to inbox '#{inbox.name}'"
  end

  def active?
    user_has_permission('administrator')
  end
end
