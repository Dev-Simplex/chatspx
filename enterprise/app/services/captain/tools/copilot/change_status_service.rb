class Captain::Tools::Copilot::ChangeStatusService < Captain::Tools::BaseTool
  def self.name
    'change_status'
  end
  description 'Change the status of a conversation (open, pending, resolved, snoozed)'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :status, type: :string, desc: 'New status: open, pending, resolved, or snoozed', required: true

  def execute(conversation_id:, status:)
    conversation = @assistant.account.conversations.find_by(display_id: conversation_id)
    return 'Conversation not found' if conversation.blank?
    return "Invalid status: #{status}" unless Conversation.statuses.key?(status)

    conversation.update!(status: status)
    "Conversation ##{conversation_id} status changed to #{status}"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
