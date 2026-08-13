class Captain::Tools::Copilot::AssignConversationService < Captain::Tools::BaseTool
  def self.name
    'assign_conversation'
  end
  description 'Assign a conversation to an agent or team'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :agent_id, type: :integer, desc: 'ID of the agent to assign (optional)'
  param :team_id, type: :integer, desc: 'ID of the team to assign (optional)'

  # Quem escolhe `agent_id`/`team_id` é o MODELO, não o operador — ele digita "distribui isso
  # pro time certo" e o copilot resolve o id sozinho. Os ids iam direto pra coluna: conversa
  # apontada pra time de OUTRA conta some da fila de todo mundo e leva o nome do time alheio
  # pro painel. Resolver ANTES de gravar é o que fecha a fronteira.
  #
  # Recusa FECHADA (não grava nada e devolve o motivo), ao contrário do HumanHandoffService,
  # que falha aberto de propósito. A diferença é quem lê o erro: lá a recusa acontece no meio
  # de um atendimento, com o dossiê já registrado e o cliente prestes a ouvir "uma pessoa vai
  # assumir" — abortar deixaria a promessa sem ninguém acionado. Aqui a chamada É a ação
  # inteira: recusar é no-op, e a string volta pro modelo, que corrige o id ou avisa o
  # operador. Ignorar em silêncio seria o pior dos três — `format_result` imprimiria
  # "team: none" como sucesso e a conversa ficaria na fila de ninguém.
  def execute(conversation_id:, agent_id: nil, team_id: nil)
    conversation = account.conversations.find_by(display_id: conversation_id)
    return 'Conversation not found' if conversation.blank?

    agent = agent_id.present? ? account.users.find_by(id: agent_id) : nil
    return "Agent #{agent_id} not found in this account" if agent_id.present? && agent.nil?

    team = team_id.present? ? account.handoff_teams.find_by(id: team_id) : nil
    return team_refusal(team_id) if team_id.present? && team.nil?

    apply_assignment(conversation, agent, team)
    format_result(conversation)
  end

  def active?
    user_has_permission('conversation_manage')
  end

  private

  def account
    @assistant.account
  end

  # Além da conta, respeita a allowlist de roteamento (`Account#handoff_teams`, PR #39). Ela
  # ficou de fora do copilot no PR original com o argumento de que aqui há humano no meio —
  # o argumento não se sustenta: o humano pede a ação, o modelo escolhe o destino e executa
  # sem confirmação (medido em produção: `snooze_conversation` já rodou sozinho). Quem
  # configurou que a IA não roteia pra um time não quer que o copilot roteie tampouco.
  # Conta sem a chave => `handoff_teams` são todos os times => nada muda.
  #
  # Distingue "não é desta conta" de "é da conta mas está fora da allowlist": sem isso a
  # recusa fica indistinguível de alucinação do modelo, mesmo critério do HumanHandoffService.
  def team_refusal(id)
    return "Team #{id} not found in this account" unless account.teams.exists?(id: id)

    Rails.logger.info("[Copilot][assign] time #{id} fora da allowlist da conta #{account.id}")
    "Team #{id} is not available for routing in this account"
  end

  def apply_assignment(conversation, agent, team)
    conversation.assignee = agent if agent
    conversation.team = team if team
    conversation.save!
  end

  def format_result(conversation)
    assignee_name = conversation.assignee&.name || 'none'
    team_name = conversation.team&.name || 'none'
    "Conversation ##{conversation.display_id} assigned to agent: #{assignee_name}, team: #{team_name}"
  end
end
