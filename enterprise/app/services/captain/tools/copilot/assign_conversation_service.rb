class Captain::Tools::Copilot::AssignConversationService < Captain::Tools::BaseTool
  def self.name
    'assign_conversation'
  end
  description 'Assign a conversation to an agent or team'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :agent_id, type: :integer, desc: 'ID of the agent to assign (optional)'
  param :team_id, type: :integer, desc: 'ID of the team to assign (optional)'

  def execute(conversation_id:, agent_id: nil, team_id: nil)
    conversation = @assistant.account.conversations.find_by(display_id: conversation_id)
    return 'Conversation not found' if conversation.blank?

    apply_assignment(conversation, agent_id, team_id)
    format_result(conversation)
  end

  def active?
    user_has_permission('conversation_manage')
  end

  private

  def apply_assignment(conversation, agent_id, team_id)
    conversation.assignee_id = agent_id if agent_id.present?
    conversation.team_id = team_id if team_id.present?
    conversation.save!
  end

  def format_result(conversation)
    assignee_name = conversation.assignee&.name || 'none'
    team_name = conversation.team&.name || 'none'
    "Conversation ##{conversation.display_id} assigned to agent: #{assignee_name}, team: #{team_name}"
  end
end
