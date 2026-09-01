class Captain::Tools::Copilot::GetConversationService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'get_conversation'
  end
  description 'Get details of a conversation including messages and contact information'

  param :conversation_id, type: :integer, desc: 'ID of the conversation to retrieve', required: true

  # O `active?` abaixo admite de propósito os papéis restritos (unassigned/participating) —
  # e era justamente para eles que a leitura vinha sem limite: o tool declarava servir a
  # quem só enxerga as próprias conversas e entregava a conta inteira, com notas privadas.
  def execute(conversation_id:)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?

    conversation.to_llm_text(include_private_messages: true)
  end

  def active?
    user_has_permission('conversation_manage') ||
      user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage')
  end
end
