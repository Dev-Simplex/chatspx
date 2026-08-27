class Captain::Tools::Copilot::GetConversationFullService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'get_conversation_full'
  end
  description 'Get complete conversation details including assignee, team, labels, timestamps, and contact history'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true

  def execute(conversation_id:)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?

    [
      format_conversation_meta(conversation),
      format_contact_info(conversation.contact),
      conversation.to_llm_text(include_private_messages: true)
    ].join("\n")
  end

  def active?
    user_has_permission('conversation_manage') ||
      user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage')
  end

  private

  def format_conversation_meta(conversation)
    lines = []
    lines << "Conversation ##{conversation.display_id}:"
    lines << "Status: #{conversation.status} | Priority: #{conversation.priority || 'none'}"
    lines << "Assignee: #{safe_name(conversation.assignee)} | Team: #{safe_name(conversation.team)}"
    lines << "Inbox: #{safe_name(conversation.inbox)} | Labels: #{conversation.label_list.join(', ').presence || 'none'}"
    lines << "Created: #{conversation.created_at.strftime('%Y-%m-%d %H:%M')}"
    lines << "Messages: #{conversation.messages.count}"
    lines.join("\n")
  end

  def safe_name(record)
    record&.name || 'none'
  end

  def format_contact_info(contact)
    return 'Contact: unknown' if contact.blank?

    # Conta dentro do alcance do usuário pelo mesmo motivo do resto do tool: o total cru
    # da conta é um número que ele não teria como obter na tela.
    total_convs = permissible_conversations.where(contact_id: contact.id).count
    "Contact: #{contact.name} | Email: #{contact.email || 'N/A'} | Phone: #{contact.phone_number || 'N/A'} | Total conversations: #{total_convs}"
  end
end
