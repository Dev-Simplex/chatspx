class Api::V1::Accounts::Conversations::AssignmentsController < Api::V1::Accounts::Conversations::BaseController
  # Puxar para si a conversa que está na fila ou com a IA é o caminho da aba "Em atendimento", e o
  # guard de time barrava isso quando a conversa era de outro time. A exceção é APERTADA: só para
  # mim, e só quando não há dono humano. Atribuir conversa de outro time a terceiros continua 403.
  skip_before_action :authorize_team_access, only: [:create]
  before_action :authorize_team_access_ou_puxar, only: [:create]

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

    # Puxou de outro time: a conversa vem junto. Senão, em caixa com isolamento por time, ela
    # sumiria da vista de quem acabou de assumir.
    Conversations::TeamHandoverService.new(conversation: @conversation, user: Current.user).perform if puxando_para_si?

    render_agent(resource)
  end

  def authorize_team_access_ou_puxar
    return if puxando_para_si?

    authorize_team_access
  end

  # Memoizado: depois do AssignmentService a conversa já tem dono, e a pergunta passaria a devolver
  # false justamente quando ela é usada para mover o time.
  def puxando_para_si?
    return @puxando_para_si if defined?(@puxando_para_si)

    @puxando_para_si = Current.user.is_a?(User) &&
                       @conversation.assignee_id.blank? &&
                       params[:assignee_id].to_s == Current.user.id.to_s
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
