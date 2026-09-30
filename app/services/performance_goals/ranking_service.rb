# CHAT-177: realizado x meta de cada atendente (scope 'users') ou time ('teams') num mes.
#
# O realizado sai das MESMAS fontes dos relatorios (nada e recalculado, senao o numero diverge e vira
# chamado): AgentSummaryBuilder / TeamSummaryBuilder, o NpsCalculator e, para o Kanban, os cartoes numa
# etapa marcada como ganho que entraram nela no mes. Os dois builders contam "resolvidas" de jeitos
# diferentes (safra do mes x eventos do mes) -- os totais de pessoas e de times NAO somam entre si.
#
# Parte de usuarios/times que EXISTEM: o builder de agente devolve uma linha por account_user, inclusive
# vinculo orfao (usuario apagado), e o ranking nao pode herdar essas linhas sem nome.
class PerformanceGoals::RankingService
  pattr_initialize [:account!, :month!, :scope!, { team_id: nil, target_ids: nil }]

  def perform
    ranked, without_goal = PerformanceGoals::Scoring.rank(rows)
    { rows: ranked, without_goal: without_goal, kanban_configured: won_stage_ids.any? }
  end

  private

  def users? = scope == 'users'

  def rows
    targets.map do |target|
      { id: target.id, name: users? ? target.available_name : target.name,
        avatar_url: users? ? target.avatar_url : nil, metrics: metrics_for(target.id) }
    end
  end

  def targets
    relation = users? ? account.users.order(:name) : account.teams.order(:name)
    relation = relation.where(id: TeamMember.where(team_id: team_id).select(:user_id)) if users? && team_id.present?
    relation = relation.where(id: target_ids) unless target_ids.nil?
    relation.to_a
  end

  def metrics_for(id)
    summary = summaries[id] || {}
    frt = summary[:avg_first_response_time]
    actuals = {
      'resolved_conversations' => summary[:resolved_conversations_count].to_i,
      'first_response_time' => frt && (frt.to_f / 60).round(1),
      'nps' => nps_scores[id],
      'kanban_wins' => won_stage_ids.any? ? kanban_wins[id].to_i : nil
    }
    actuals.to_h { |metric, actual| [metric, { actual: actual, goal: goals[[target_type, id, metric]]&.dig(:value) }] }
  end

  def target_type = users? ? 'user' : 'team'

  def goals
    @goals ||= PerformanceGoal.in_force(account, month)
  end

  # Mes no fuso de relatorios da conta. O `until` do DateRangeHelper e EXCLUSIVO (`...`): vai o primeiro
  # instante do mes seguinte, nao o 23:59:59 do ultimo dia.
  def period
    @period ||= begin
      start = month.in_time_zone(account.reporting_timezone.presence || Time.zone.name).beginning_of_month
      start...start.next_month
    end
  end

  def summaries
    @summaries ||= begin
      builder = users? ? V2::Reports::AgentSummaryBuilder : V2::Reports::TeamSummaryBuilder
      params = { since: period.begin.to_i.to_s, until: period.end.to_i.to_s }
      builder.new(account: account, params: params).build.index_by { |row| row[:id] }
    end
  end

  # Mesmo recorte do relatorio de NPS: respondidas, com nota, confiaveis, criadas no mes. Sem resposta = sem
  # dado (nil), nunca zero.
  def nps_scores
    @nps_scores ||= begin
      key = users? ? :assigned_agent_id : 'conversations.team_id'
      relation = NpsResponse.where(account: account, status: :responded, created_at: period).where.not(score: nil).trusted
      relation = relation.joins(:conversation) unless users?
      relation.group(key, :score).count
              .group_by { |(id, _), _| id }
              .transform_values { |pairs| Reports::NpsCalculator.score_from_counts(pairs.to_h { |(_, score), n| [score, n] }) }
    end
  end

  def won_stage_ids
    @won_stage_ids ||= FunnelStage.joins(:funnel).where(funnels: { account_id: account.id })
                                  .where("funnel_stages.settings ->> 'counts_as_won' = 'true'").pluck(:id)
  end

  # Cartao numa etapa de ganho que ENTROU nela no mes. O Kanban so guarda o ultimo moved_at: cartao tirado
  # da etapa deixa de contar (limitacao aceita e declarada na tela). Cartao sem conversa entra no ranking de
  # pessoas (pelo assignee do cartao) mas nao no de times.
  def kanban_wins
    @kanban_wins ||= begin
      key = users? ? Arel.sql('COALESCE(funnel_items.assignee_id, conversations.assignee_id)') : 'conversations.team_id'
      FunnelItem.left_joins(:conversation).where(funnel_stage_id: won_stage_ids)
                .where('COALESCE(funnel_items.moved_at, funnel_items.created_at) >= ? AND ' \
                       'COALESCE(funnel_items.moved_at, funnel_items.created_at) < ?', period.begin, period.end)
                .group(key).count
    end
  end
end
