class Captain::Tools::Copilot::GetContactConversationsService < Captain::Tools::BaseTool
  def self.name
    'get_contact_conversations'
  end
  description 'Get conversation history for a contact'

  param :contact_id, type: :integer, desc: 'ID of the contact', required: true
  param :limit, type: :integer, desc: 'Maximum number of conversations to return (default: 10)'

  def execute(contact_id:, limit: 10)
    contact = Contact.find_by(id: contact_id, account_id: @assistant.account_id)
    return 'Contact not found' if contact.nil?

    conversations = contact.conversations.order(created_at: :desc).limit(limit)
    return "No conversations found for contact ##{contact_id}" if conversations.empty?

    results = conversations.map { |c| format_conversation(c) }
    "Conversations for contact '#{contact.name}' (##{contact_id}):\n#{results.join("\n")}"
  end

  def active?
    user_has_permission('contact_manage')
  end

  private

  def format_conversation(conversation)
    assignee = conversation.assignee&.name || 'unassigned'
    "- ##{conversation.display_id}: status=#{conversation.status}, assignee=#{assignee}, " \
      "inbox=#{conversation.inbox&.name}, created=#{conversation.created_at.strftime('%Y-%m-%d')}"
  end
end
