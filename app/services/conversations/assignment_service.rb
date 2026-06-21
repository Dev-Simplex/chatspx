class Conversations::AssignmentService
  def initialize(conversation:, assignee_id:, assignee_type: nil)
    @conversation = conversation
    @assignee_id = assignee_id
    @assignee_type = assignee_type
  end

  def perform
    agent_bot_assignment? ? assign_agent_bot : assign_agent
  end

  private

  attr_reader :conversation, :assignee_id, :assignee_type

  def assign_agent
    conversation.assignee = assignee
    conversation.assignee_agent_bot = nil
    conversation.save!
    assignee
  end

  def assign_agent_bot
    return unless agent_bot

    conversation.assignee = nil
    conversation.assignee_agent_bot = agent_bot
    conversation.save!
    agent_bot
  end

  def assignee
    @assignee ||= conversation.account.users.find_by(id: assignee_id)
  end

  # C8 (defesa em profundidade, no-op silencioso — padrão do service): espelho captain
  # só é atribuível se o assistant for elegível à inbox da conversa. O 422 explícito
  # para a UI mora no AssignmentsController; aqui cobre os caminhos in-process.
  def agent_bot
    @agent_bot ||= begin
      bot = AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
      bot = nil if bot&.captain? && !eligible_captain_bot?(bot)
      bot
    end
  end

  def eligible_captain_bot?(bot)
    conversation.inbox.captain_assistants.exists?(id: bot.captain_assistant_id)
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end
end
