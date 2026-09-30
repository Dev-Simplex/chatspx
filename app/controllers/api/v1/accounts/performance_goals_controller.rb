# CHAT-177: definir metas (so quem gerencia) e escolher quem enxerga o ranking (so gerente total).
#
#   GET   performance_goals?month=AAAA-MM -> metas EM VIGOR no mes, so dos alvos que quem chama gerencia
#   PUT   performance_goals                -> grava o lote numa transacao; um item invalido recusa tudo (422)
#   PATCH performance_goals/visibility     -> managers | own | everyone
class Api::V1::Accounts::PerformanceGoalsController < Api::V1::Accounts::BaseController
  before_action :ensure_manager, except: :visibility

  def index
    render json: goals_payload
  end

  def update
    return render_error(I18n.t('errors.performance_goals.past_month'), :unprocessable_entity) if month < current_month
    return render_forbidden unless items.all? { |item| access.manages?(item[:target_type], item[:target_id]) }

    save_goals!
    render json: goals_payload
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence, target_type: e.record.target_type,
                   target_id: e.record.target_id, metric: e.record.metric }, status: :unprocessable_entity
  end

  def visibility
    return render_forbidden unless access.can_change_visibility?

    Current.account.update!(goals_visibility: params[:visibility])
    render json: { visibility: access.visibility }
  end

  private

  # Salvar a tela sem mexer num campo nao grava linha nova: senao o "em vigor desde" andaria todo mes.
  def save_goals!
    in_force = PerformanceGoal.in_force(Current.account, month)
    PerformanceGoal.transaction do
      items.each do |item|
        value = item[:value].presence&.to_d
        current = in_force.dig([item[:target_type], item[:target_id].to_i, item[:metric]], :value)
        next if value == current&.to_d

        PerformanceGoal.find_or_initialize_by(account: Current.account, month: month, target_type: item[:target_type],
                                              target_id: item[:target_id], metric: item[:metric]).update!(value: value)
      end
    end
  end

  def goals_payload
    in_force = PerformanceGoal.in_force(Current.account, month)
    {
      month: month.strftime('%Y-%m'), editable: month >= current_month, visibility: access.visibility,
      can_change_visibility: access.can_change_visibility?,
      users: users.map { |user| target_json(user, 'user', in_force).merge(team_ids: team_ids_by_user[user.id] || []) },
      teams: teams.map { |team| target_json(team, 'team', in_force) }
    }
  end

  def target_json(target, type, in_force)
    goals = PerformanceGoal::METRICS.to_h do |metric|
      goal = in_force[[type, target.id, metric]]
      [metric, goal && { value: goal[:value], since_month: goal[:since_month].strftime('%Y-%m') }]
    end
    { id: target.id, name: type == 'user' ? target.available_name : target.name,
      avatar_url: type == 'user' ? target.avatar_url : nil, goals: goals }
  end

  def users
    relation = Current.account.users.order(:name)
    access.managed_user_ids.nil? ? relation : relation.where(id: access.managed_user_ids)
  end

  def teams
    relation = Current.account.teams.order(:name)
    access.managed_team_ids.nil? ? relation : relation.where(id: access.managed_team_ids)
  end

  def team_ids_by_user
    @team_ids_by_user ||= TeamMember.where(team_id: Current.account.teams.select(:id)).pluck(:user_id, :team_id)
                                    .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  def items
    @items ||= Array(params[:goals]).map { |item| item.permit(:target_type, :target_id, :metric, :value).to_h.symbolize_keys }
  end

  def ensure_manager
    render_forbidden unless access.manager?
  end

  def access
    @access ||= PerformanceGoals::Access.new(user: Current.user, account: Current.account)
  end

  def month
    @month ||= PerformanceGoals::Month.parse(params[:month], Current.account)
  end

  def current_month
    PerformanceGoals::Month.current(Current.account)
  end

  def render_forbidden
    render_error(I18n.t('errors.performance_goals.forbidden'), :forbidden)
  end

  def render_error(message, status)
    render json: { error: message }, status: status
  end
end
