class Captain::Tools::Copilot::SnoozeConversationService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'snooze_conversation'
  end
  description 'Snooze a conversation for a specified number of hours'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :hours, type: :integer, desc: 'Number of hours to snooze the conversation', required: true

  def execute(conversation_id:, hours:)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?

    conversation.update!(status: :snoozed, snoozed_until: hours.hours.from_now)
    "Conversation ##{conversation_id} snoozed until #{conversation.snoozed_until.strftime('%Y-%m-%d %H:%M')}"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
