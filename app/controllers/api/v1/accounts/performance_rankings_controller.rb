# CHAT-177: GET /api/v1/accounts/:account_id/performance_ranking?month=AAAA-MM&scope=users|teams&team_id=
#
# O corte e AQUI, no servidor: o atendente nunca recebe o numero de um colega que a tela nao deve mostrar.
#   managers -> atendente leva 403;
#   own      -> `rows` vazio, so `me`;
#   everyone -> ranking dos times de que participa; nas linhas dos colegas `actual` e `goal` vem null.
class Api::V1::Accounts::PerformanceRankingsController < Api::V1::Accounts::BaseController
  def show
    return render_forbidden unless access.can_view_ranking?
    return render_forbidden unless team_filter_allowed?

    result = ranking(scope_param, target_ids)
    render json: payload(result)
  end

  private

  def payload(result)
    rows = result[:rows]
    rows = access.visibility == 'own' ? [] : rows.map { |row| hide_numbers(row) } unless access.manager?
    {
      month: month.strftime('%Y-%m'), scope: scope_param, visibility: access.visibility, can_manage: access.manager?,
      kanban_configured: result[:kanban_configured], generated_at: Time.current.iso8601,
      me: me_row(result), rows: rows, without_goal: access.manager? ? result[:without_goal] : []
    }
  end

  def ranking(scope, ids)
    PerformanceGoals::RankingService.new(account: Current.account, month: month, scope: scope,
                                         team_id: (params[:team_id] if scope == 'users'), target_ids: ids).perform
  end

  # nil = todos. Gerente: o que ele gerencia. Atendente: ele mesmo (own) ou os times dele (everyone).
  def target_ids
    users = scope_param == 'users'
    return users ? access.managed_user_ids : access.managed_team_ids if access.manager?
    return users ? [Current.user.id] : [] if access.visibility == 'own'

    users ? (TeamMember.where(team_id: access.member_team_ids).pluck(:user_id) | [Current.user.id]) : access.member_team_ids
  end

  def team_filter_allowed?
    return true if params[:team_id].blank? || (access.managed_team_ids.nil? && access.manager?)

    allowed = access.manager? ? access.managed_team_ids : access.member_team_ids
    allowed.include?(params[:team_id].to_i)
  end

  # O proprio desempenho, sempre com numeros completos. nil para quem nao tem meta nem dado.
  def me_row(result)
    row = own_row(result)
    row if row && row[:metrics].values.any? { |m| m[:goal] || m[:actual].to_f.positive? }
  end

  def own_row(result)
    row = (result[:rows] + result[:without_goal]).find { |r| r[:id] == Current.user.id } if scope_param == 'users'
    row || ranking('users', [Current.user.id]).values_at(:rows, :without_goal).flatten.first
  end

  def hide_numbers(row)
    return row if row[:id] == Current.user.id && scope_param == 'users'

    row.merge(metrics: row[:metrics].transform_values { |m| m.merge(actual: nil, goal: nil) })
  end

  def access
    @access ||= PerformanceGoals::Access.new(user: Current.user, account: Current.account)
  end

  def month
    @month ||= PerformanceGoals::Month.parse(params[:month], Current.account)
  end

  def scope_param
    params[:scope] == 'teams' ? 'teams' : 'users'
  end

  def render_forbidden
    render json: { error: I18n.t('errors.performance_goals.forbidden') }, status: :forbidden
  end
end
