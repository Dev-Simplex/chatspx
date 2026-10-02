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
  # Mesmo no-op quando a trava de teste do assistant (only_contact_phones) não libera o
  # contato: a IA não fala com ele, então não pode ser dona da conversa (CHAT-171). Idem
  # para conversa ou contato com etiqueta que a conta tirou da IA (CHAT-180).
  def agent_bot
    @agent_bot ||= begin
      bot = AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
      bot = nil if bot&.captain? && !eligible_captain_bot?(bot)
      bot
    end
  end

  def eligible_captain_bot?(bot)
    conversation.inbox.captain_assistants.exists?(id: bot.captain_assistant_id) &&
      Captain::Behavior::ContactPhoneLock.new(bot.captain_assistant).allows?(conversation.contact) &&
      Captain::Behavior::SkipLabelsLock.new(conversation.account).allows?(conversation)
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end
end
