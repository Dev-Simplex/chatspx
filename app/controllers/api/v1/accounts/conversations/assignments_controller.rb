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
    return render_captain_assignment_not_eligible if ineligible_captain_assignment?
    return render_takeover_request_required if takeover_blocked?

    resource = Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform

    render_agent(resource)
  end

  # D1 (Fase 3) — guard (a) das 3 superfícies humanas. Mesma lógica do guard
  # captain logo abaixo: automação/macro/round-robin NÃO passam pelo controller
  # (são in-process), então o guard aqui não as afeta — e isso é intencional.
  # No-op com o takeover_request_gate desligado.
  def takeover_blocked?
    return false if agent_bot_assignment?

    Conversations::TakeoverGate.new(
      conversation: @conversation,
      actor: Current.user,
      new_assignee_id: params[:assignee_id]
    ).blocked?
  end

  # 422 + meta com o dono ATUAL, p/ a UI oferecer "Solicitar atendimento" sem
  # precisar de outra request (molde: messages_controller#render_assignment_required).
  def render_takeover_request_required
    owner = @conversation.assignee
    existing = ConversationTakeoverRequest.find_by(
      conversation_id: @conversation.id, requester_id: Current.user&.id, status: :pending
    )
    render json: {
      error: I18n.t('conversations.takeover_request_gate.request_required'),
      error_code: 'takeover_request_required',
      meta: {
        current_assignee: owner && {
          id: owner.id,
          name: owner.try(:available_name) || owner.name,
          type: 'User'
        },
        team: @conversation.team && { id: @conversation.team.id, name: @conversation.team.name },
        existing_request: existing && { id: existing.id, status: existing.status, created_at: existing.created_at.to_i }
      }
    }, status: :unprocessable_entity
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

  # C8: erro EXPLÍCITO p/ UI — o dropdown C2 já filtra por inbox_ids, então o 422 é
  # cinto de segurança para API direta/corrida de elegibilidade.
  def ineligible_captain_assignment?
    return false unless agent_bot_assignment? && requested_agent_bot&.captain?

    !@conversation.inbox.captain_assistants.exists?(id: requested_agent_bot.captain_assistant_id)
  end

  def render_captain_assignment_not_eligible
    render json: { error: I18n.t('conversations.captain.assignment_not_eligible') }, status: :unprocessable_entity
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
