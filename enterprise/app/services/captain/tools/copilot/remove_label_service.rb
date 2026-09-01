class Captain::Tools::Copilot::RemoveLabelService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'remove_label'
  end
  description 'Remove a label from a conversation'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :label, type: :string, desc: 'Label to remove', required: true

  def execute(conversation_id:, label:)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?

    conversation.label_list.remove(label)
    conversation.save!

    "Label '#{label}' removed from conversation ##{conversation_id}. Current labels: #{conversation.label_list.join(', ')}"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
