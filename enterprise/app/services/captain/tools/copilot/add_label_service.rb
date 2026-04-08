class Captain::Tools::Copilot::AddLabelService < Captain::Tools::BaseTool
  def self.name
    'add_label'
  end
  description 'Add a label to a conversation'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :label, type: :string, desc: 'Label to add', required: true

  def execute(conversation_id:, label:)
    conversation = @assistant.account.conversations.find_by(display_id: conversation_id)
    return 'Conversation not found' if conversation.blank?

    conversation.label_list.add(label)
    conversation.save!

    "Label '#{label}' added to conversation ##{conversation_id}. Current labels: #{conversation.label_list.join(', ')}"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
