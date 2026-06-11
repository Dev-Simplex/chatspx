class Api::V1::Accounts::Conversations::AssignmentsController < Api::V1::Accounts::Conversations::BaseController
  # assigns agent/team to a conversation
  def create
    if params.key?(:assignee_id) || agent_bot_assignment?
      set_agent
    elsif params.key?(:team_id)
      set_team
    else
      render json: nil
    end
  end

  private

  def set_agent
    return render_captain_assignment_forbidden if forbidden_captain_assignment?

    resource = Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform

    render_agent(resource)
  end

  # Atribuição MANUAL de espelho captain é admin-only (D-3). Automação/macro/tool
  # não passam pelo controller (in-process) — o guard mora SÓ aqui de propósito.
  def forbidden_captain_assignment?
    return false unless agent_bot_assignment?
    return false unless requested_agent_bot&.captain?

    !admin_user?
  end

  def requested_agent_bot
    @requested_agent_bot ||= AgentBot.accessible_to(Current.account).find_by(id: params[:assignee_id])
  end

  # Safe navigation OBRIGATÓRIA: AgentBot-token chega aqui com Current.account_user = nil
  # (whitelist BOT_ACCESSIBLE_ENDPOINTS) — guard ingênuo daria NoMethodError/500.
  def admin_user?
    Current.user.is_a?(User) && Current.account_user&.administrator?
  end

  def render_captain_assignment_forbidden
    render json: { error: I18n.t('conversations.captain.assignment_forbidden') }, status: :forbidden
  end

  def render_agent(resource)
    case resource
    when User
      render partial: 'api/v1/models/agent', formats: [:json], locals: { resource: resource }
    when AgentBot
      render partial: 'api/v1/models/agent_bot_slim', formats: [:json], locals: { resource: resource }
    else
      render json: nil
    end
  end

  def set_team
    @team = Current.account.teams.find_by(id: params[:team_id])
    @conversation.update!(team: @team)
    render json: @team
  end

  def agent_bot_assignment?
    params[:assignee_type].to_s == 'AgentBot'
  end
end
