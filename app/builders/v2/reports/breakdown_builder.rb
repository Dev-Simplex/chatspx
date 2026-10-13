# Um numero dos relatorios aberto por grupo, para os graficos do painel de Relatorios:
# CSAT por agente, NPS por time, SLA por politica e por time. Cada linha traz o id, o nome,
# o total do grupo e o valor; os recortes (periodo, caixa) sao os mesmos das telas de CSAT/NPS/SLA.
class V2::Reports::BreakdownBuilder
  KINDS = %w[csat_by_agent nps_by_team sla_by_policy sla_by_team].freeze

  def initialize(account, params)
    @account = account
    @params = params
  end

  def supported?
    KINDS.include?(@params[:kind].to_s) && (!@params[:kind].to_s.start_with?('sla') || @account.respond_to?(:applied_slas))
  end

  def build
    send(@params[:kind])
  end

  private

  def csat_by_agent
    ratings = csat_scope.where.not(assigned_agent_id: nil).group(:assigned_agent_id, :rating).count
    names = @account.users.where(id: ratings.keys.map(&:first)).pluck(:id, :name).to_h
    rows_from(ratings, names) { |by_value| { total: by_value.values.sum, value: pct(by_value[4].to_i + by_value[5].to_i, by_value.values.sum) } }
  end

  def nps_by_team
    scores = nps_scope.joins(:conversation).where.not(conversations: { team_id: nil })
                      .group('conversations.team_id', :score).count
    names = @account.teams.where(id: scores.keys.map(&:first)).pluck(:id, :name).to_h
    rows_from(scores, names) { |by_value| nps_row(by_value) }
  end

  def sla_by_policy
    sla_rows(sla_scope.group(:sla_policy_id), @account.sla_policies)
  end

  def sla_by_team
    sla_rows(sla_scope.joins(:conversation).where.not(conversations: { team_id: nil }).group('conversations.team_id'), @account.teams)
  end

  # {[grupo, valor] => n} -> uma linha por grupo, a maior primeiro
  def rows_from(counts, names)
    grouped = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    counts.each { |(group_id, value), count| grouped[group_id][value] += count }
    grouped.map { |group_id, by_value| { id: group_id, name: names[group_id] || "##{group_id}" }.merge(yield(by_value)) }
           .sort_by { |row| -row[:total] }
  end

  def nps_row(by_score)
    total = by_score.values.sum
    promoters = by_score.select { |score, _| score >= 9 }.values.sum
    detractors = by_score.select { |score, _| score <= 6 }.values.sum
    { total: total, value: Reports::NpsCalculator.score(promoters: promoters, detractors: detractors, total: total) }
  end

  def sla_rows(grouped, owners)
    totals = grouped.count
    missed = grouped.missed.count
    names = owners.where(id: totals.keys).pluck(:id, :name).to_h
    rows = totals.map do |group_id, total|
      { id: group_id, name: names[group_id] || "##{group_id}", total: total, missed: missed[group_id].to_i,
        value: pct(total - missed[group_id].to_i, total) }
    end
    rows.sort_by { |row| -row[:total] }
  end

  def csat_scope
    @account.csat_survey_responses.filter_by_created_at(range).filter_by_inbox_id(@params[:inbox_id])
  end

  def nps_scope
    base = @account.nps_responses.filter_by_inbox_id(@params[:inbox_id]).where(status: :responded).where.not(score: nil).trusted
    range ? base.where(created_at: range) : base
  end

  def sla_scope
    @account.applied_slas.filter_by_date_range(range).filter_by_inbox_id(@params[:inbox_id])
  end

  def range
    return if @params[:since].blank? || @params[:until].blank?

    Time.zone.at(@params[:since].to_i)..Time.zone.at(@params[:until].to_i)
  end

  def pct(part, whole)
    return 0.0 if whole.to_i.zero?

    ((part.to_f / whole) * 100).round(1)
  end
end
