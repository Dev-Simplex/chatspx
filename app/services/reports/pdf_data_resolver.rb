# Resolve os dados de cada relatorio para o PDF brandeado.
# Unico ponto do backend que conhece a forma de cada relatorio: o resto do
# pipeline (service/job/layout) e generico. Reusa os MESMOS builders/controllers
# existentes — nao recria metrica.
class Reports::PdfDataResolver # rubocop:disable Metrics/ClassLength
  TZ = 'America/Manaus'.freeze
  TZ_OFFSET = -4 # America/Manaus (UTC-4) — V2::ReportBuilder espera offset em horas.
  WEEKDAY_LABELS = %w[Seg Ter Qua Qui Sex Sáb Dom].freeze
  WEEKDAY_ORDER = [1, 2, 3, 4, 5, 6, 0].freeze # remapeia Dom-primeiro do #wday para Seg-primeiro.

  SUMMARY_BUILDERS = {
    'agent' => 'V2::Reports::AgentSummaryBuilder',
    'inbox' => 'V2::Reports::InboxSummaryBuilder',
    'team' => 'V2::Reports::TeamSummaryBuilder',
    'label' => 'V2::Reports::LabelSummaryBuilder'
  }.freeze

  SUMMARY_TITLES = {
    'agent' => 'Relatório de Atendentes', 'inbox' => 'Relatório de Caixas',
    'team' => 'Relatório de Times', 'label' => 'Relatório de Etiquetas'
  }.freeze

  def initialize(account:, report_type:, filters:)
    @account = account
    @report_type = report_type.to_s
    @filters = normalize_filters(filters)
  end

  # since/until podem chegar como Integer (corpo JSON do front), mas os builders
  # nativos esperam String epoch — DateRangeHelper#parse_date_time usa
  # DateTime.strptime(_, '%s'), que estoura "no implicit conversion of Integer into String".
  def normalize_filters(filters)
    normalized = (filters || {}).with_indifferent_access
    %i[since until].each do |key|
      normalized[key] = normalized[key].to_s if normalized[key].is_a?(Numeric)
    end
    normalized
  end

  def resolve # rubocop:disable Metrics/CyclomaticComplexity
    case @report_type
    when 'nps' then nps_data
    when 'csat' then csat_data
    when 'bot' then bot_data
    when 'conversations' then conversations_data
    when 'overview' then overview_data
    when 'sla' then sla_data
    when 'funnel' then funnel_data
    when 'agent_assignment' then agent_assignment_data
    when 'agent', 'inbox', 'team', 'label' then summary_data(@report_type)
    else
      raise ArgumentError, "report_type desconhecido: #{@report_type}"
    end
  end

  private

  # ======================= NPS =======================
  # Mesma fonte única do card/API (Reports::NpsCalculator) — score inteiro, taxa
  # de resposta em coorte e delta em pontos vs período anterior.
  def nps_data
    cohort = nps_cohort
    responded = cohort.where(status: :responded).where.not(score: nil).trusted
    calc = Reports::NpsCalculator.new(
      responded_scope: responded,
      sent_count: cohort.where(status: %i[sent responded expired]).count,
      previous_score: previous_nps_score
    )
    kpis = nps_kpis(calc, cohort)

    {
      report_type: 'nps', title: 'Relatório de NPS', period: period_meta,
      overline: 'Experiência do Cliente · Confidencial',
      subtitle: nps_subtitle(kpis),
      base_label: "#{kpis[:total]} avaliações válidas",
      kpis: kpis, headline: nps_headline(kpis),
      verdict: nps_verdict(calc),
      distribution: nps_distribution(responded),
      agents: nps_by_agent(responded), detractors: nps_detractor_rows(responded)
    }
  end

  def nps_headline(kpis)
    return { emoji: '🤔', text: 'Nenhum cliente respondeu a pesquisa de recomendação no período.' } if kpis[:total].to_i.zero?

    { emoji: kpis[:nps_score].to_i >= 50 ? '💚' : '🧡',
      text: "A nota NPS é #{kpis[:nps_score]}: #{kpis[:promoters]} clientes recomendariam a empresa e #{kpis[:detractors]} não recomendariam." }
  end

  NPS_DETRACTOR_LIMIT = 10

  # Quem nao recomendaria (0 a 6), os mais recentes primeiro: e quem o gestor precisa procurar.
  def nps_detractor_rows(responded)
    responded.detractors.includes(:conversation, :contact, :assigned_agent).order(answered_at: :desc, id: :desc)
             .limit(NPS_DETRACTOR_LIMIT).map { |row| nps_detractor_row(row) }
  end

  def nps_detractor_row(row)
    { id: conversation_label(row.conversation), contact: row.contact&.name.presence || 'Sem nome',
      agent: row.assigned_agent&.name || 'sem atendente', score: row.score,
      comment: row.comment.presence&.truncate(160), date: format_date(row.answered_at || row.created_at) }
  end

  def nps_kpis(calc, cohort)
    {
      total: calc.total, nps_score: calc.score,
      response_rate: calc.response_rate,
      promoters: calc.promoters, passives: calc.passives, detractors: calc.detractors,
      promoters_pct: calc.promoters_pct, passives_pct: calc.passives_pct,
      detractors_pct: calc.detractors_pct,
      blocked: cohort.where(status: :dismissed).count,
      reliable: calc.reliable?, min_sample: Reports::NpsCalculator::MIN_SAMPLE,
      delta: calc.delta
    }
  end

  # Subtítulo com tendência em pontos (quando há período anterior comparável).
  def nps_subtitle(kpis)
    base = "Nota NPS #{kpis[:nps_score]}, com #{kpis[:total]} clientes respondendo no período."
    return base if kpis[:delta].nil? || kpis[:delta].zero?

    arrow = kpis[:delta].positive? ? '▲' : '▼'
    "#{base} #{arrow} #{kpis[:delta].abs} pontos #{kpis[:delta].positive? ? 'a mais' : 'a menos'} que no período anterior."
  end

  # Veredito neutro quando a amostra é baixa (não pinta vermelho um N=1).
  def nps_verdict(calc)
    return metric_verdict(metric: :nps, value: calc.score, human: calc.score.to_s, label: 'NPS') if calc.reliable?

    {
      kind: :attention, emoji: 'ℹ️', title: 'Amostra insuficiente',
      level: :warn, word: 'amostra baixa', metric_label: 'NPS',
      value_human: calc.score.to_s, goal_human: metric_goal_human(:nps),
      body: "Apenas #{calc.total} avaliações válidas (mínimo #{Reports::NpsCalculator::MIN_SAMPLE} para leitura confiável). " \
            "Interprete o NPS de #{calc.score} com cautela."
    }
  end

  def nps_distribution(responded)
    counts = responded.group(:score).count
    (0..10).reverse_each.map do |score|
      { score: score, count: counts[score].to_i, band: nps_band(score) }
    end
  end

  def nps_by_agent(responded)
    scores_by_agent = group_scores_by_agent(responded)
    names = agent_names(scores_by_agent.keys.compact)
    scores_by_agent.map { |agent_id, scores| nps_agent_stat(agent_id, scores, names) }
                   .sort_by { |agent| -agent[:total] }
  end

  def group_scores_by_agent(responded)
    grouped = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    responded.group(:assigned_agent_id).group(:score).count.each do |(agent_id, score), count|
      grouped[agent_id][score] += count
    end
    grouped
  end

  def nps_agent_stat(agent_id, scores, names)
    promoters = scores.select { |score, _| score.between?(9, 10) }.values.sum
    detractors = scores.select { |score, _| score.between?(0, 6) }.values.sum
    total = scores.values.sum
    { id: agent_id, name: entity_name(agent_id, names), total: total,
      nps_score: Reports::NpsCalculator.score(promoters: promoters, detractors: detractors, total: total),
      positive_pct: pct(promoters, total) }
  end

  # Base filtrada (agente/inbox), sem recorte de data — reusada pelo coorte atual
  # e pelo período anterior.
  def nps_filtered_base
    @nps_filtered_base ||= @account.nps_responses
                                   .filter_by_assigned_agent_id(@filters[:user_ids])
                                   .filter_by_inbox_id(@filters[:inbox_id])
                                   .filter_by_team_id(@filters[:team_id])
  end

  # Coorte por created_at — mesma base do numerador e do denominador da taxa.
  def nps_cohort
    @nps_cohort ||= range.present? ? nps_filtered_base.where(created_at: range) : nps_filtered_base
  end

  # NPS do período imediatamente anterior de mesma duração (nil se indisponível).
  def previous_nps_score
    return nil if range.blank?

    duration = range.last - range.first
    previous_range = (range.first - duration)...range.first
    counts = nps_filtered_base.where(created_at: previous_range)
                              .where(status: :responded).where.not(score: nil).trusted
                              .group(:score).count
    return nil if counts.values.sum.zero?

    Reports::NpsCalculator.score_from_counts(counts)
  end

  def nps_band(score)
    return 'detractor' if score <= 6
    return 'passive' if score <= 8

    'promoter'
  end

  # ======================= CSAT =======================
  def csat_data
    scope = csat_scope
    total = scope.count
    by_rating = scope.group(:rating).count
    kpis = csat_kpis(total, by_rating)
    {
      report_type: 'csat', title: 'Relatório de CSAT', period: period_meta,
      overline: 'Satisfação do Cliente · Confidencial',
      subtitle: "Índice de satisfação de #{br_number(kpis[:satisfaction])}% (notas 4 e 5) sobre #{total} respostas no período.",
      base_label: "#{total} respostas",
      kpis: kpis, headline: csat_headline(kpis), comparison: csat_comparison(kpis),
      verdict: metric_verdict(metric: :csat, value: kpis[:satisfaction], human: "#{br_number(kpis[:satisfaction])}%", label: 'Satisfação'),
      distribution: csat_distribution(by_rating),
      feedbacks: csat_feedbacks(scope), low_ratings: csat_low_ratings(scope),
      agents: csat_by_agent(scope)
    }
  end

  def csat_kpis(total, by_rating)
    satisfied = (by_rating[4].to_i + by_rating[5].to_i)
    {
      total: total, satisfaction: pct(satisfied, total), avg_rating: csat_avg(by_rating, total),
      response_rate: csat_response_rate(total),
      satisfied: satisfied, neutral: by_rating[3].to_i,
      unsatisfied: (by_rating[1].to_i + by_rating[2].to_i)
    }
  end

  def csat_distribution(by_rating)
    colors = { 5 => '#2dc46f', 4 => '#95de64', 3 => '#ffc53d', 2 => '#ff7a45', 1 => '#e54666' }
    (1..5).reverse_each.map do |rating|
      { score: rating, count: by_rating[rating].to_i, color: colors[rating] }
    end
  end

  def csat_feedbacks(scope)
    scope.where.not(feedback_message: [nil, '']).order(created_at: :desc).limit(12).map do |row|
      { rating: row.rating, feedback: row.feedback_message.to_s.truncate(160),
        agent: row.assigned_agent&.name || 'Sem atribuição', contact: row.contact&.name,
        date: format_date(row.created_at) }
    end
  end

  def csat_by_agent(scope)
    grouped = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    scope.group(:assigned_agent_id).group(:rating).count.each do |(agent_id, rating), count|
      grouped[agent_id][rating] += count
    end
    names = agent_names(grouped.keys.compact)
    grouped.map { |agent_id, ratings| csat_agent_stat(agent_id, ratings, names) }
           .sort_by { |agent| -agent[:total] }
  end

  def csat_agent_stat(agent_id, ratings, names)
    total = ratings.values.sum
    satisfied = ratings[4].to_i + ratings[5].to_i
    { id: agent_id, name: entity_name(agent_id, names), total: total,
      satisfaction: pct(satisfied, total) }
  end

  def csat_avg(by_rating, total)
    return 0.0 if total.zero?

    sum = by_rating.sum { |rating, count| rating * count }
    (sum.to_f / total).round(2)
  end

  def csat_scope
    @csat_scope ||= csat_scope_for(range)
  end

  def csat_scope_for(window)
    scope = @account.csat_survey_responses.includes(:contact, :assigned_agent)
    scope = scope.filter_by_created_at(window) if window.present?
    scope = scope.filter_by_assigned_agent_id(@filters[:user_ids])
    scope = scope.filter_by_inbox_id(@filters[:inbox_id])
    scope = scope.filter_by_team_id(@filters[:team_id])
    scope.filter_by_rating(@filters[:rating])
  end

  # Mesma comparacao do PDF de Conversas: a janela anterior, de mesma duracao, com os mesmos filtros.
  def csat_comparison(kpis)
    prev = previous_csat_kpis
    return {} if prev.nil?

    { satisfaction: metric_delta(kpis[:satisfaction], prev[:satisfaction], lower_better: false),
      total: metric_delta(kpis[:total], prev[:total], lower_better: false),
      avg: metric_delta(kpis[:avg_rating], prev[:avg_rating], lower_better: false) }
  end

  def previous_csat_kpis
    return nil if range.blank?

    previous = csat_scope_for((range.first - (range.last - range.first))...range.first)
    total = previous.count
    total.zero? ? nil : csat_kpis(total, previous.group(:rating).count)
  end

  CSAT_MOOD = [[80, '😀'], [60, '😐'], [0, '😞']].freeze

  def csat_headline(kpis)
    return { emoji: '🤔', text: 'Nenhum cliente deu nota no período.' } if kpis[:total].zero?

    emoji = CSAT_MOOD.find { |limit, _| kpis[:satisfaction] >= limit }.last
    { emoji: emoji, text: "Os clientes deram #{kpis[:total]} notas e #{br_number(kpis[:satisfaction])}% ficaram satisfeitos " \
                          "(nota 4 ou 5). #{kpis[:unsatisfied]} ficaram insatisfeitos." }
  end

  CSAT_LOW_LIMIT = 10

  # As notas baixas (1 e 2), as mais recentes primeiro: e quem o gestor precisa procurar.
  def csat_low_ratings(scope)
    scope.where(rating: [1, 2]).includes(:conversation).order(created_at: :desc).limit(CSAT_LOW_LIMIT).map { |row| csat_low_row(row) }
  end

  def csat_low_row(row)
    { id: conversation_label(row.conversation), contact: row.contact&.name.presence || 'Sem nome',
      agent: row.assigned_agent&.name || 'sem atendente', rating: row.rating,
      feedback: row.feedback_message.presence&.truncate(160), date: format_date(row.created_at) }
  end

  def conversation_label(conversation)
    conversation ? "##{conversation.display_id}" : '—'
  end

  # 80.9 -> "80,9" (o PDF mostrava ponto decimal).
  def br_number(value)
    ActiveSupport::NumberHelper.number_to_rounded(value, precision: 1, separator: ',', delimiter: '.', strip_insignificant_zeros: true)
  end

  def csat_response_rate(total)
    sent = @account.messages.input_csat
    sent = sent.where(created_at: range) if range.present?
    pct(total, sent.count)
  end

  # ======================= BOT =======================
  def bot_data
    metrics = V2::Reports::BotMetricsBuilder.new(@account, builder_params).metrics
    {
      report_type: 'bot', title: 'Relatório do Robô', period: period_meta,
      overline: 'Atendimento automático · Confidencial',
      subtitle: "O robô resolveu sozinho #{metrics[:resolution_rate]}% das #{metrics[:conversation_count]} conversas que passaram por ele.",
      base_label: "#{metrics[:conversation_count]} conversas",
      kpis: bot_kpis(metrics),
      verdict: bot_verdict(metrics, :bot_resolution_rate, metrics[:resolution_rate], 'Resolveu sozinho'),
      verdict_secondary: bot_verdict(metrics, :bot_handoff_rate, metrics[:handoff_rate], 'Passou para uma pessoa'),
      timeseries: {
        resolutions: count_series('bot_resolutions_count'),
        handoffs: count_series('bot_handoffs_count')
      },
      inboxes: bot_by_inbox, handoffs: bot_handoff_rows
    }
  end

  BOT_HANDOFF_LIMIT = 10

  # As ultimas conversas que o robo passou para uma pessoa (a mesma lista do numero da tela).
  def bot_handoff_rows
    drilldown('bot_handoffs_count').top(BOT_HANDOFF_LIMIT).map do |row|
      { id: "##{row[:display_id]}", contact: row[:contact_name].presence || 'Sem nome', inbox: row[:inbox_name],
        agent: row[:agent_name].presence || 'sem atendente', status: STATUS_PT.fetch(row[:status], row[:status]),
        date: Time.zone.at(row[:created_at]).in_time_zone(TZ).strftime('%d/%m %H:%M') }
    end
  end

  def bot_kpis(metrics)
    {
      conversations: metrics[:conversation_count], messages: metrics[:message_count],
      resolution_rate: metrics[:resolution_rate], handoff_rate: metrics[:handoff_rate],
      resolutions: bot_event_count('conversation_bot_resolved'),
      handoffs: bot_event_count('conversation_bot_handoff')
    }
  end

  # Card de veredito de uma taxa do bot. Sem conversas com bot → nil (sem card).
  def bot_verdict(metrics, metric, value, label)
    return nil if metrics[:conversation_count].to_i.zero?

    metric_verdict(metric: metric, value: value, human: "#{value}%", label: label)
  end

  def bot_by_inbox
    rows = @account.inboxes.select(&:active_bot?).map { |inbox| bot_inbox_row(inbox) }
    rows.sort_by { |row| -row[:conversations] }
  end

  def bot_inbox_row(inbox)
    convs = @account.conversations.where(inbox_id: inbox.id)
    convs = convs.where(created_at: range) if range.present?
    total = convs.count
    resolutions = bot_event_count('conversation_bot_resolved', inbox.id)
    { name: inbox.name, conversations: total, resolutions: resolutions,
      handoffs: bot_event_count('conversation_bot_handoff', inbox.id),
      resolution_rate: pct(resolutions, total) }
  end

  def bot_event_count(name, inbox_id = nil)
    scope = @account.reporting_events.where(name: name)
    scope = scope.where(created_at: range) if range.present?
    scope = scope.joins(:conversation).where(conversations: { inbox_id: inbox_id }) if inbox_id
    scope.distinct.count(:conversation_id)
  end

  # ======================= CONVERSAS =======================
  def conversations_data
    summary = V2::Reports::Conversations::MetricBuilder.new(@account, builder_params(type: :account)).summary
    comparison = conversations_comparison(summary, previous_conversations_summary)
    signals = conversations_signals(summary)
    heatmap = weekday_hour_heatmap('conversations_count')
    {
      report_type: 'conversations', title: 'Relatório de Conversas', period: period_meta,
      overline: 'Operação · Confidencial',
      subtitle: conversations_subtitle(summary),
      base_label: "#{summary[:conversations_count]} conversas",
      headline: conversations_headline(summary, comparison),
      kpis: conversations_kpis(summary),
      comparison: comparison,
      highlight: signals.any? ? conversations_highlight(signals) : nil,
      attention: signals.any? ? conversations_attention(signals) : nil,
      trends: account_trends,
      heatmap: heatmap, heatmap_insight: heatmap_peak_insight(heatmap),
      table: conversations_table(summary),
      appendix: conversations_appendix(summary)
    }
  end

  # ---- Anexo: as conversas por tras dos numeros (o mesmo recorte do painel de detalhe da tela) ----
  # Visual, para ler sem esforco: as mais demoradas em barras, e o periodo agrupado por dia (a data sai da linha),
  # com tempo curto ("51 min") e a 1a resposta colorida pela meta.
  APPENDIX_LIMIT = 100
  APPENDIX_SLOWEST = 10
  STATUS_PT = { 'open' => 'Aberta', 'resolved' => 'Resolvida', 'pending' => 'Pendente', 'snoozed' => 'Adiada' }.freeze
  WEEKDAYS_PT = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado].freeze

  def conversations_appendix(summary)
    rows = drilldown('conversations_count').top(APPENDIX_LIMIT)
    slowest = drilldown('avg_first_response_time').top(APPENDIX_SLOWEST)
    times = appendix_times((rows + slowest).pluck(:id).uniq)
    {
      total: summary[:conversations_count].to_i, shown: rows.size,
      goal: format_seconds(Reports::PdfBenchmarks.goal(:first_response)),
      slowest: appendix_slowest(slowest, times), days: appendix_days(rows, times)
    }
  end

  def drilldown(metric)
    V2::Reports::Conversations::DrilldownBuilder.new(@account, builder_params(type: :account, metric: metric))
  end

  # 1a resposta e resolucao de cada conversa, na mesma coluna (com ou sem horario comercial) dos numeros.
  def appendix_times(conversation_ids)
    column = business_hours? ? :value_in_business_hours : :value
    ReportingEvent.where(conversation_id: conversation_ids, name: %w[first_response conversation_resolved])
                  .order(:created_at).pluck(:conversation_id, :name, column)
                  .each_with_object({ first_response: {}, resolution: {} }) do |(conversation_id, name, value), times|
      times[name == 'first_response' ? :first_response : :resolution][conversation_id] = value
    end
  end

  def appendix_slowest(rows, times)
    longest = rows.filter_map { |row| row[:value] }.max.to_f
    rows.map do |row|
      appendix_row(row, times).merge(bar_pct: longest.positive? ? ((row[:value].to_f / longest) * 100).round : 0)
    end
  end

  def appendix_days(rows, times)
    rows.group_by { |row| Time.zone.at(row[:created_at]).in_time_zone(TZ).to_date }.map do |date, day_rows|
      { title: "#{WEEKDAYS_PT[date.wday]}, #{date.strftime('%d/%m')}", rows: day_rows.map { |row| appendix_row(row, times) } }
    end
  end

  def appendix_row(row, times)
    first = times[:first_response][row[:id]]
    resolution = times[:resolution][row[:id]]
    {
      id: "##{row[:display_id]}", contact: row[:contact_name].presence || 'Sem nome', inbox: row[:inbox_name],
      agent: row[:agent_name].presence || 'Sem agente', status: STATUS_PT.fetch(row[:status], row[:status]),
      status_key: row[:status], time: Time.zone.at(row[:created_at]).in_time_zone(TZ).strftime('%H:%M'),
      first: first ? short_duration(first) : 'sem resposta', first_level: first_level(first),
      resolution: resolution ? short_duration(resolution) : 'em aberto'
    }
  end

  def first_level(seconds)
    seconds ? Reports::PdfBenchmarks.status(seconds, :first_response)[:level] : :none
  end

  # "51 min", "1 h 20 min", "4 min 35 s", "3 dias e 2 h": no maximo duas unidades (o mesmo jeito da tela).
  def short_duration(seconds)
    total = seconds.to_f.round
    return "#{total} s" if total < 60
    return total < 600 && (total % 60).positive? ? "#{total / 60} min #{total % 60} s" : "#{total / 60} min" if total < 3600
    return (total % 3600) >= 60 ? "#{total / 3600} h #{(total % 3600) / 60} min" : "#{total / 3600} h" if total < 86_400

    short_days(total)
  end

  def short_days(total)
    days = total / 86_400
    hours = (total % 86_400) / 3600
    "#{days} #{days == 1 ? 'dia' : 'dias'}#{" e #{hours} h" if hours.positive?}"
  end

  def conversations_subtitle(summary)
    with_inbox_scope(
      if summary[:avg_first_response_time].to_i.positive?
        "#{summary[:conversations_count]} conversas no período · 1ª resposta média de #{format_seconds(summary[:avg_first_response_time])}."
      else
        "#{summary[:conversations_count]} conversas no período."
      end
    )
  end

  # ---- Clareza Total: comparação com período anterior, manchete, herói/vilão, legenda ----
  def previous_conversations_summary
    params = previous_builder_params
    return nil if params.nil?

    V2::Reports::Conversations::MetricBuilder.new(@account, params).summary
  rescue StandardError => e
    Rails.logger.warn("[report_pdf] período anterior indisponível: #{e.message}")
    nil
  end

  # Janela imediatamente anterior, de mesma duração.
  def previous_builder_params
    return nil if range.blank?

    duration = range.last - range.first
    { since: (range.first - duration).to_i.to_s, until: range.first.to_i.to_s,
      inbox_id: @filters[:inbox_id], business_hours: business_hours?, type: :account }
  end

  def conversations_comparison(summary, previous)
    return {} if previous.blank?

    {
      conversations: metric_delta(summary[:conversations_count], previous[:conversations_count], lower_better: false),
      first_response: metric_delta(summary[:avg_first_response_time], previous[:avg_first_response_time], lower_better: true),
      resolution: metric_delta(summary[:avg_resolution_time], previous[:avg_resolution_time], lower_better: true),
      resolutions: metric_delta(summary[:resolutions_count], previous[:resolutions_count], lower_better: false)
    }
  end

  # better é direção-aware: para tempos (lower_better) a queda conta como melhora.
  # Sem base anterior (previous == 0) não há comparação — better/delta ficam nil.
  def metric_delta(current, previous, lower_better:)
    current = current.to_f
    previous = previous.to_f
    blank = { current: current, previous: previous, delta_pct: nil, better: nil, lower_better: lower_better }
    return blank if previous.zero?

    delta = current - previous
    blank.merge(delta_pct: ((delta.abs / previous) * 100).round, better: delta_better(delta, lower_better))
  end

  def delta_better(delta, lower_better)
    return nil if delta.zero?

    lower_better ? delta.negative? : delta.positive?
  end

  def conversations_resolution_rate(summary)
    total = summary[:conversations_count].to_i
    return 0 if total.zero?

    ((summary[:resolutions_count].to_f / total) * 100).round.clamp(0, 100)
  end

  # Métricas-chave avaliadas pelo semáforo, p/ escolher herói (melhor) e vilão (pior).
  # ratio = desempenho contínuo vs meta (menor = melhor) — desempata herói/vilão quando
  # várias métricas caem na mesma faixa de cor.
  def conversations_signals(summary)
    rate = conversations_resolution_rate(summary)
    [
      { label: '1ª resposta', value: summary[:avg_first_response_time].to_f,
        human: format_seconds(summary[:avg_first_response_time]), metric: :first_response, kind: :time },
      { label: 'tempo de resolução', value: summary[:avg_resolution_time].to_f,
        human: format_seconds(summary[:avg_resolution_time]), metric: :resolution, kind: :time },
      { label: 'taxa de resolução', value: rate, human: "#{rate}%", metric: :resolution_rate, kind: :rate }
    ].select { |signal| signal_has_data?(signal, summary) }
      .map { |signal| signal.merge(status: Reports::PdfBenchmarks.status(signal[:value], signal[:metric]), ratio: signal_ratio(signal)) }
  end

  # Sem conversa ou sem tempo medido não há o que julgar: "--" não está "dentro da meta".
  def signal_has_data?(signal, summary)
    signal[:kind] == :rate ? summary[:conversations_count].to_i.positive? : signal[:value].positive?
  end

  # Razão vs meta, normalizada para "menor = melhor" nas duas direções.
  def signal_ratio(signal)
    goal = Reports::PdfBenchmarks.goal(signal[:metric]).to_f
    return 99.0 if goal.zero?

    signal[:kind] == :rate ? goal / [signal[:value], 1].max : signal[:value] / goal
  end

  def conversations_highlight(signals)
    best = signals.min_by { |signal| signal[:ratio] }
    verdict_card(best, kind: :highlight)
  end

  def conversations_attention(signals)
    worst = signals.max_by { |signal| signal[:ratio] }
    if worst[:status][:level] == :good
      return { kind: :all_good, emoji: '👍', title: 'Tudo no verde', level: :good, word: 'bom',
               metric_label: 'Todos os indicadores', value_human: nil, goal_human: nil,
               body: 'Todos os indicadores estão dentro da meta — mantenha o ritmo.' }
    end

    verdict_card(worst, kind: :attention)
  end

  # Veredito estruturado p/ os cards de Destaque / Ponto de atenção do PDF.
  # Mantém emoji/title/body (compatibilidade) e expõe os campos separados
  # (metric_label/value_human/goal_human/level/word) p/ a nova hierarquia visual.
  def verdict_card(signal, kind:)
    preset = { highlight: { emoji: '🏆', title: 'Destaque' },
               attention: { emoji: '⚠️', title: 'Ponto de atenção' } }.fetch(kind)
    {
      kind: kind, emoji: preset[:emoji], title: preset[:title],
      level: signal[:status][:level], word: signal[:status][:word],
      metric_label: signal[:label].capitalize, value_human: signal[:human],
      goal_human: goal_human_for(signal), body: signal_phrase(signal)
    }
  end

  def goal_human_for(signal)
    goal = Reports::PdfBenchmarks.goal(signal[:metric])
    signal[:kind] == :rate ? "#{goal}%" : format_seconds(goal)
  end

  # Veredito de um único indicador (CSAT/NPS) p/ o card de veredito do PDF.
  # Mesma estrutura de verdict_card (kind/emoji/title/level/word/metric_label/
  # value_human/goal_human/body), porém a partir de uma métrica avulsa.
  def metric_verdict(metric:, value:, human:, label:)
    status = Reports::PdfBenchmarks.status(value, metric)
    level = status[:level]
    good = level == :good
    {
      kind: good ? :highlight : :attention,
      emoji: good ? '🏆' : '⚠️',
      title: good ? 'Destaque' : 'Ponto de atenção',
      level: level, word: status[:word],
      metric_label: label, value_human: human, goal_human: metric_goal_human(metric),
      body: "#{label}: #{human} (meta #{metric_goal_human(metric)}) — #{status[:word]}."
    }
  end

  def metric_goal_human(metric)
    goal = Reports::PdfBenchmarks.goal(metric)
    metric == :nps ? goal.to_s : "#{goal}%"
  end

  def signal_phrase(signal)
    "#{signal[:label].capitalize}: #{signal[:human]} (meta #{goal_human_for(signal)}) — #{signal[:status][:word]}."
  end

  def conversations_headline(summary, comparison)
    total = summary[:conversations_count].to_i
    return { emoji: '🤔', text: 'Nenhuma conversa no período. Ajuste o intervalo ou os filtros para ver o movimento.' } if total.zero?

    mood = headline_mood(comparison)
    { emoji: { good: '📈', flat: '📊', bad: '📉' }[mood], text: headline_text(total, comparison, mood) }
  end

  def headline_mood(comparison)
    return :flat if comparison.blank?

    flags = comparison.values.pluck(:better)
    good = flags.count(true)
    bad = flags.count(false)
    return :good if good > bad
    return :bad if bad > good

    :flat
  end

  def headline_text(total, comparison, mood)
    tag = { good: ' Período bom! 🎉', flat: ' Período estável.', bad: ' Fique de olho neste período.' }[mood]
    "Sua equipe atendeu #{total} conversas#{headline_vol_clause(comparison[:conversations])}" \
      "#{headline_frt_clause(comparison[:first_response])}.#{tag}"
  end

  def headline_vol_clause(cmp)
    return '' if cmp.nil? || cmp[:delta_pct].nil? || cmp[:delta_pct].zero?

    " — #{cmp[:delta_pct]}% #{cmp[:better] ? 'a mais' : 'a menos'} que o período anterior"
  end

  def headline_frt_clause(cmp)
    return '' if cmp.nil? || cmp[:better].nil?

    cmp[:better] ? ' e os clientes esperaram menos pela 1ª resposta' : ', mas a espera pela 1ª resposta aumentou'
  end

  def heatmap_peak_insight(heatmap)
    values = heatmap[:values]
    return nil if values.blank? || values.flatten.compact.sum.zero?

    peak = heatmap_peak_cell(values)
    day = %w[segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado domingo][peak[:day]]
    "Pico de movimento: #{day} por volta das #{format('%02dh', peak[:hour])}. Reforce a equipe nesse horário."
  end

  def heatmap_peak_cell(values)
    best = { day: 0, hour: 0, value: -1 }
    values.each_with_index do |row, day_i|
      row.each_with_index do |count, hour|
        best = { day: day_i, hour: hour, value: count.to_i } if count.to_i > best[:value]
      end
    end
    best
  end

  def conversations_kpis(summary)
    {
      conversations: summary[:conversations_count], incoming: summary[:incoming_messages_count],
      outgoing: summary[:outgoing_messages_count], resolutions: summary[:resolutions_count],
      avg_first_response: format_seconds(summary[:avg_first_response_time]),
      avg_resolution: format_seconds(summary[:avg_resolution_time]),
      avg_reply: format_seconds(summary[:reply_time]),
      # valores crus (segundos / %) p/ o template avaliar o semáforo (princ. 2/5).
      frt_seconds: summary[:avg_first_response_time].to_f,
      resolution_seconds: summary[:avg_resolution_time].to_f,
      resolution_rate: conversations_resolution_rate(summary)
    }
  end

  def conversations_table(summary)
    {
      columns: [{ label: 'Métrica' }, { label: 'Valor', align: 'right' }],
      rows: [
        ['Tempo de 1ª resposta (médio)', format_seconds(summary[:avg_first_response_time])],
        ['1ª resposta — p50', format_seconds(summary[:p50_first_response_time])],
        ['1ª resposta — p90', format_seconds(summary[:p90_first_response_time])],
        ['1ª resposta após atribuição (médio)', format_seconds(summary[:avg_first_response_time_after_assignment])],
        ['Após atribuição — p50', format_seconds(summary[:p50_first_response_time_after_assignment])],
        ['Após atribuição — p90', format_seconds(summary[:p90_first_response_time_after_assignment])],
        ['Tempo de resolução (médio)', format_seconds(summary[:avg_resolution_time])],
        ['Tempo de resposta (médio)', format_seconds(summary[:reply_time])],
        ['Conversas resolvidas', summary[:resolutions_count].to_s]
      ]
    }
  end

  # ======================= VISÃO GERAL =======================
  def overview_data
    open = overview_scope.open
    kpis = { open: open.count, unattended: open.unattended.count,
             unassigned: open.unassigned.count, pending: overview_scope.pending.count }
    {
      report_type: 'overview', title: 'Relatório de Visão Geral', period: snapshot_period,
      overline: 'Situação Operacional · Confidencial',
      subtitle: "#{kpis[:open]} conversas abertas neste instante · #{kpis[:unattended]} ainda não atendidas.",
      base_label: "#{kpis[:open]} conversas abertas",
      headline: overview_headline(kpis), kpis: kpis,
      waiting: overview_waiting,
      traffic_heatmap: weekday_hour_heatmap('conversations_count', **trailing_window),
      resolutions_heatmap: weekday_hour_heatmap('resolutions_count', **trailing_window),
      agents: overview_group_rows(:assignee_id, agent_names_all),
      teams: overview_group_rows(:team_id, team_names_all)
    }
  end

  # O mesmo recorte da tela (Api::V2::Accounts::LiveReportsController#load_conversations): o PDF ignorava a caixa.
  def overview_scope
    scope = @account.conversations
    @filters[:inbox_id].present? ? scope.where(inbox_id: @filters[:inbox_id]) : scope
  end

  def overview_headline(kpis)
    return { emoji: '✅', text: 'Nenhuma conversa aberta agora. Está tudo em dia.' } if kpis[:open].zero?
    return { emoji: '✅', text: "Há #{kpis[:open]} conversas abertas e nenhuma esperando resposta. A fila está em dia." } if kpis[:unattended].zero?

    { emoji: '⏳', text: "Há #{kpis[:open]} conversas abertas: #{kpis[:unattended]} esperam resposta e #{kpis[:unassigned]} estão sem atendente." }
  end

  OVERVIEW_WAITING = 10

  # Quem espera resposta ha mais tempo (a mesma lista do numero "nao atendidas" da tela).
  def overview_waiting
    rows = V2::Reports::LiveDrilldownBuilder.new(overview_scope, metric: 'unattended').page(1)[:payload].first(OVERVIEW_WAITING)
    rows.map { |row| overview_waiting_row(row) }
  end

  def overview_waiting_row(row)
    { id: "##{row[:display_id]}", contact: row[:contact_name].presence || 'Sem nome', inbox: row[:inbox_name],
      agent: row[:agent_name].presence || 'ninguém', team: row[:team_name].presence || '—', waiting: short_duration(row[:value]),
      since: Time.zone.at(row[:value_at]).in_time_zone(TZ).strftime('%d/%m às %H:%M'),
      level: first_level(row[:value]) }
  end

  def overview_group_rows(group_key, names)
    open = overview_scope.open
    extra = { unattended: open.unattended.group(group_key).count, unassigned: open.unassigned.group(group_key).count }
    counts = open.group(group_key).count.reject { |id, _| id.nil? }.sort_by { |_, count| -count }
    most = counts.first&.last
    counts.map { |id, count| overview_group_row(id, count, names, extra).merge(bar_pct: bar_pct(count, most)) }
  end

  def overview_group_row(id, count, names, extra)
    { name: names[id] || "##{id}", open: count, unattended: extra[:unattended][id].to_i, unassigned: extra[:unassigned][id].to_i }
  end

  # Largura da barra (0-100) de um valor frente ao maior da lista.
  def bar_pct(value, most)
    most.to_f.positive? ? ((value.to_f / most) * 100).round : 0
  end

  # ======================= SLA (enterprise) =======================
  def sla_data
    return sla_unavailable unless ChatwootApp.enterprise? && defined?(AppliedSla)

    scope = sla_scope
    total = scope.count
    missed = scope.missed.count
    hit_rate = sla_hit_rate(total, missed)
    {
      report_type: 'sla', title: 'Relatório de SLA', period: period_meta,
      overline: 'Nível de Serviço · Confidencial',
      subtitle: "#{hit_rate} das #{total} conversas com prazo cumpriram o combinado · #{missed} passaram do prazo.",
      base_label: "#{total} conversas com prazo",
      kpis: { total: total, hit_rate: hit_rate, breaches: missed,
              compliance: pct(total - missed, total) },
      verdict: sla_verdict(total, missed, hit_rate),
      by_policy: sla_by_policy(scope),
      breaches_table: sla_breaches_table(scope)
    }
  end

  # Card de veredito do hit rate. Sem SLAs aplicados → nil (sem card).
  def sla_verdict(total, missed, hit_rate)
    return nil if total.zero?

    metric_verdict(metric: :sla_hit_rate, value: pct(total - missed, total),
                   human: hit_rate, label: 'Cumpriram o prazo')
  end

  def sla_unavailable
    { report_type: 'sla', title: 'Relatório de SLA', period: period_meta,
      kpis: {}, by_policy: [], breaches_table: { columns: [], rows: [] },
      unavailable: 'Recurso de SLA não está habilitado nesta conta.' }
  end

  def sla_scope
    scope = AppliedSla.where(account_id: @account.id).includes(:conversation, :sla_policy)
    scope = scope.filter_by_date_range(range) if range.present?
    scope = scope.filter_by_assigned_agent_id(@filters[:assigned_agent_id] || @filters[:user_ids])
    scope = scope.filter_by_inbox_id(@filters[:inbox_id])
    scope = scope.filter_by_team_id(@filters[:team_id])
    scope.filter_by_sla_policy_id(@filters[:sla_policy_id])
  end

  def sla_by_policy(scope)
    totals = scope.group(:sla_policy_id).count
    missed = scope.missed.group(:sla_policy_id).count
    names = @account.sla_policies.where(id: totals.keys).pluck(:id, :name).to_h
    totals.sort_by { |_, count| -count }.map do |policy_id, total|
      breached = missed[policy_id].to_i
      { name: names[policy_id] || "##{policy_id}", total: total, breached: breached,
        hit_rate: pct(total - breached, total) }
    end
  end

  def sla_breaches_table(scope)
    rows = scope.missed.order(created_at: :desc).limit(20).map { |applied| sla_breach_row(applied) }
    { columns: [{ label: 'Conversa' }, { label: 'Prazo combinado' }, { label: 'Atendente' }, { label: 'Situação' }],
      rows: rows }
  end

  def sla_breach_row(applied)
    conv = applied.conversation
    [conv&.display_id ? "##{conv.display_id}" : '—',
     applied.sla_policy&.name || '—',
     conv&.assignee&.name || 'Sem atribuição',
     sla_status_label(applied.sla_status)]
  end

  def sla_hit_rate(total, missed)
    return '100%' if total.zero?

    "#{br_number(pct(total - missed, total))}%"
  end

  def sla_status_label(status)
    { 'missed' => 'Passou do prazo', 'active_with_misses' => 'Aberta, já passou do prazo' }[status.to_s] || status.to_s
  end

  # ======================= FUNIL (Kanban) =======================
  # Snapshot operacional do funil — espelha o "Painel do funil" da board.
  # Reusa Kanban::FunnelReportService (mesma fonte da view live), nao recria metrica.
  def funnel_data
    funnel = @account.funnels.find(@filters[:funnel_id])
    report = Kanban::FunnelReportService.new(funnel: funnel).perform
    funnel_payload(funnel.name, report)
  end

  def funnel_payload(name, report)
    totals = report[:totals]
    cards = totals[:cards].to_i
    open_count = totals[:by_status].to_h['open'].to_i
    {
      report_type: 'funnel', title: "CRM KANBAN · #{name}", period: snapshot_period,
      overline: 'CRM KANBAN · Gestão de Funil · Confidencial',
      subtitle: "Funil \"#{name}\" do Kanban · #{cards} cards · #{open_count} em aberto · #{totals[:overdue]} atrasados.",
      base_label: "#{cards} cards", funnel_name: name,
      kpis: totals.merge(open: open_count),
      stage_chart: funnel_stage_series(report[:stages]),
      workload_chart: funnel_workload_series(report[:workload]),
      stages_table: funnel_stages_table(report[:stages]),
      workload_table: funnel_workload_table(report[:workload])
    }
  end

  def funnel_stage_series(stages)
    stages.map { |stage| { label: stage[:name], value: stage[:count] } }
  end

  def funnel_workload_series(workload)
    workload.map { |row| { label: funnel_workload_label(row), value: row[:count] } }
  end

  def funnel_workload_label(row)
    row[:name].presence || "##{row[:assignee_id]}"
  end

  def funnel_stages_table(stages)
    rows = stages.map do |stage|
      [stage[:name], stage[:count].to_s, funnel_age_label(stage[:avg_age_seconds]),
       stage[:unassigned].to_i.to_s, stage[:overdue].to_i.to_s]
    end
    { columns: [{ label: 'Coluna' }, { label: 'Cards', align: 'right' }, { label: 'Tempo médio', align: 'right' },
                { label: 'Sem responsável', align: 'right' }, { label: 'Atrasados', align: 'right' }],
      rows: rows }
  end

  def funnel_workload_table(workload)
    rows = workload.map { |row| [funnel_workload_label(row), row[:count].to_s] }
    { columns: [{ label: 'Atendente' }, { label: 'Cards', align: 'right' }], rows: rows }
  end

  def funnel_age_label(seconds)
    seconds.to_i.positive? ? format_seconds(seconds) : '—'
  end

  # ======================= ATRIBUIÇÕES (quem atribuiu pra quem) =======================
  # Reusa V2::Reports::AgentAssignmentBuilder (mesma fonte da aba "Atribuições") — não recria métrica.
  def agent_assignment_data
    builder = V2::Reports::AgentAssignmentBuilder.new(account: @account, params: assignment_params)
    rows = builder.build
    totals = assignment_totals(rows)
    active = rows.count { |row| row[:received_total].to_i.positive? || row[:assigned_to_others].to_i.positive? }
    {
      report_type: 'agent_assignment', title: 'Relatório de Atribuições', period: period_meta,
      overline: 'Distribuição de Atribuições · Confidencial',
      subtitle: assignment_subtitle(totals, active),
      base_label: "#{totals[:received_total]} atribuições",
      headline: assignment_headline(totals, active), kpis: totals.merge(agents: active),
      source_segments: assignment_source_segments(totals),
      people: assignment_people(rows), pairs: assignment_pairs(builder.matrix)
    }
  end

  def assignment_headline(totals, active)
    total = totals[:received_total].to_i
    return { emoji: '🤔', text: 'Nenhuma conversa foi entregue a um atendente no período.' } if total.zero?

    { emoji: '🔀', text: "#{total} conversas foram entregues a #{active} atendentes. " \
                        "#{assignment_pct(totals[:received_auto], total)}% chegaram pelo rodízio e " \
                        "#{assignment_pct(totals[:received_manual], total)}% porque alguém passou." }
  end

  # Uma linha por atendente: barra do total recebido e de onde veio (a conta fecha: total = soma das 4 origens).
  def assignment_people(rows)
    active = rows.select { |row| row[:received_total].to_i.positive? || row[:assigned_to_others].to_i.positive? }
                 .sort_by { |row| -row[:received_total].to_i }
    most = active.first&.dig(:received_total)
    active.map { |row| assignment_person(row).merge(bar_pct: bar_pct(row[:received_total], most)) }
  end

  def assignment_person(row)
    { name: row[:name].presence || "##{row[:id]}", total: row[:received_total].to_i, manual: row[:received_manual].to_i,
      auto: row[:received_auto].to_i, self: row[:self_assigned].to_i, other: assignment_other(row),
      to_others: row[:assigned_to_others].to_i }
  end

  def assignment_other(row)
    [row[:received_total].to_i - row[:received_manual].to_i - row[:received_auto].to_i - row[:self_assigned].to_i, 0].max
  end

  ASSIGNMENT_PAIRS = 10

  def assignment_pairs(matrix)
    top = matrix.first(ASSIGNMENT_PAIRS)
    most = top.first&.dig(:count)
    top.map { |pair| { from: pair[:from_name], to: pair[:to_name], count: pair[:count], bar_pct: bar_pct(pair[:count], most) } }
  end

  def assignment_pct(value, total)
    ((value.to_i * 100.0) / total).round
  end

  def assignment_params
    { since: @filters[:since], until: @filters[:until],
      team_id: @filters[:team_id], inbox_id: @filters[:inbox_id] }
  end

  def assignment_totals(rows)
    totals = %i[received_total received_manual received_auto self_assigned assigned_to_others].index_with do |key|
      rows.sum { |row| row[key].to_i }
    end
    totals.merge(received_other: rows.sum { |row| assignment_other(row) })
  end

  def assignment_subtitle(totals, active)
    return 'Nenhuma atribuição registrada no período.' if totals[:received_total].zero?

    "#{totals[:received_total]} atribuições no período, distribuídas entre #{active} atendentes."
  end

  # Split da origem das atribuições recebidas p/ a barra de composição. "Outras" cobre
  # automação/bot/api que entram no total mas não nas 3 faixas principais.
  def assignment_source_segments(totals)
    segments = [
      { label: 'Alguém passou', value: totals[:received_manual], color: '#2dc46f' },
      { label: 'Rodízio', value: totals[:received_auto], color: '#1f93ff' },
      { label: 'Pegou para si', value: totals[:self_assigned], color: '#95de64' }
    ]
    segments << { label: 'Outras (IA, automação...)', value: totals[:received_other], color: '#bfbfbf' } if totals[:received_other].positive?
    segments
  end

  def assignment_short_name(name)
    name.to_s.split(/\s+/).first.presence || '—'
  end

  def assignment_columns
    [{ label: 'Atendente' }, { label: 'Recebidas (total)', align: 'right' }, { label: '↳ Manuais', align: 'right' },
     { label: '↳ Automáticas', align: 'right' }, { label: '↳ Auto-assumidas', align: 'right' },
     { label: 'Atribuiu a outros', align: 'right' }]
  end

  def assignment_row(row)
    [row[:name] || "##{row[:id]}", row[:received_total].to_i.to_s, row[:received_manual].to_i.to_s,
     row[:received_auto].to_i.to_s, row[:self_assigned].to_i.to_s, row[:assigned_to_others].to_i.to_s]
  end

  # ======================= SUMMARY (agent/inbox/team/label) =======================
  def summary_data(metric_type)
    rows = SUMMARY_BUILDERS[metric_type].constantize.new(account: @account, params: summary_params(metric_type)).build
    kpis = summary_kpis(rows)
    signals = summary_verdict_signals(rows)
    comparison = summary_comparison(metric_type, kpis)
    noun = summary_noun(metric_type)
    {
      report_type: metric_type, title: SUMMARY_TITLES[metric_type], period: period_meta,
      overline: 'Desempenho · Confidencial', noun: noun,
      subtitle: with_inbox_scope("#{kpis[:entities]} #{noun} com atividade · #{kpis[:conversations]} conversas no período."),
      base_label: "#{kpis[:conversations]} conversas",
      headline: conversations_headline({ conversations_count: kpis[:conversations] }, comparison),
      kpis: kpis, comparison: comparison,
      highlight: signals.any? ? conversations_highlight(signals) : nil,
      attention: signals.any? ? conversations_attention(signals) : nil,
      trends: metric_type == 'label' ? {} : account_trends,
      people: summary_people(rows, metric_type),
      table: summary_table(rows, metric_type)
    }
  end

  def summary_noun(metric_type)
    SUMMARY_TITLES[metric_type].sub('Relatório de ', '').downcase
  end

  # Mesma comparacao do PDF de Conversas, com o periodo anterior das MESMAS entidades.
  def summary_comparison(metric_type, kpis)
    previous = previous_summary_kpis(metric_type)
    return {} if previous.nil?

    {
      conversations: metric_delta(kpis[:conversations], previous[:conversations], lower_better: false),
      first_response: metric_delta(kpis[:frt_seconds], previous[:frt_seconds], lower_better: true),
      resolution: metric_delta(kpis[:resolution_seconds], previous[:resolution_seconds], lower_better: true),
      resolutions: metric_delta(kpis[:resolved], previous[:resolved], lower_better: false)
    }
  end

  def previous_summary_kpis(metric_type)
    params = previous_builder_params
    return nil if params.nil?

    summary_kpis(SUMMARY_BUILDERS[metric_type].constantize.new(account: @account, params: params.merge(type: metric_type.to_sym)).build)
  rescue StandardError => e
    Rails.logger.warn("[report_pdf] período anterior indisponível (#{metric_type}): #{e.message}")
    nil
  end

  # Uma linha por pessoa/caixa/time/etiqueta, com barra do volume e a 1a resposta colorida pela meta.
  def summary_people(rows, metric_type)
    names = summary_names(metric_type)
    visible = rows.select { |row| row[:conversations_count].to_i.positive? }.sort_by { |row| -row[:conversations_count].to_i }
    most = visible.first&.dig(:conversations_count).to_f
    visible.map { |row| summary_person(row, metric_type, names, most) }
  end

  def summary_person(row, metric_type, names, most)
    {
      name: row[:name] || entity_name(row[:id], names), channel: (names.dig(:channels, row[:id]) if metric_type == 'inbox'),
      conversations: row[:conversations_count].to_i, resolved: row[:resolved_conversations_count].to_i,
      bar_pct: most.positive? ? ((row[:conversations_count].to_f / most) * 100).round : 0,
      first: short_or_dash(row[:avg_first_response_time]), first_level: first_level(row[:avg_first_response_time]),
      resolution: short_or_dash(row[:avg_resolution_time]), reply: short_or_dash(row[:avg_reply_time])
    }
  end

  def short_or_dash(seconds)
    seconds ? short_duration(seconds) : '—'
  end

  # Sinais do veredito da MÉDIA das entidades, reusando a lógica de Conversas
  # (1ª resposta, resolução, taxa de resolução). Sem entidades ativas → vazio.
  def summary_verdict_signals(rows)
    with_data = rows.select { |row| row[:conversations_count].to_i.positive? }
    return [] if with_data.empty?

    conversations_signals(
      avg_first_response_time: avg_metric(with_data, :avg_first_response_time),
      avg_resolution_time: avg_metric(with_data, :avg_resolution_time),
      conversations_count: rows.sum { |row| row[:conversations_count].to_i },
      resolutions_count: rows.sum { |row| row[:resolved_conversations_count].to_i }
    )
  end

  def summary_params(metric_type)
    { type: metric_type.to_sym, since: @filters[:since], until: @filters[:until],
      inbox_id: @filters[:inbox_id], business_hours: business_hours? }
  end

  def summary_kpis(rows)
    with_data = rows.select { |row| row[:conversations_count].to_i.positive? }
    frt = avg_metric(with_data, :avg_first_response_time)
    resolution = avg_metric(with_data, :avg_resolution_time)
    {
      entities: with_data.size,
      conversations: rows.sum { |row| row[:conversations_count].to_i },
      resolved: rows.sum { |row| row[:resolved_conversations_count].to_i },
      avg_first_response: format_seconds(frt), avg_resolution: format_seconds(resolution),
      # crus, para o semaforo e a comparacao (como no PDF de Conversas)
      frt_seconds: frt.to_f, resolution_seconds: resolution.to_f
    }
  end

  def summary_table(rows, metric_type)
    names = summary_names(metric_type)
    visible = rows.select { |row| row[:conversations_count].to_i.positive? }
    visible = rows if visible.empty?
    visible = visible.sort_by { |row| -row[:conversations_count].to_i }
    { columns: summary_columns(metric_type), rows: visible.map { |row| summary_row(row, metric_type, names) } }
  end

  def summary_columns(metric_type)
    cols = [{ label: SUMMARY_TITLES[metric_type].sub('Relatório de ', '').sub(/s$/, '') }]
    cols << { label: 'Canal' } if metric_type == 'inbox'
    cols + [{ label: 'Conversas', align: 'right' }, { label: 'Resolvidas', align: 'right' },
            { label: 'FRT médio', align: 'right' }, { label: 'Resolução média', align: 'right' },
            { label: 'Resposta média', align: 'right' }]
  end

  def summary_row(row, metric_type, names)
    cells = [row[:name] || entity_name(row[:id], names)]
    cells << (names.dig(:channels, row[:id]) || '—') if metric_type == 'inbox'
    cells + [row[:conversations_count].to_i.to_s, row[:resolved_conversations_count].to_i.to_s,
             format_seconds(row[:avg_first_response_time]), format_seconds(row[:avg_resolution_time]),
             format_seconds(row[:avg_reply_time])]
  end

  def summary_names(metric_type)
    case metric_type
    when 'agent' then @account.users.pluck(:id, :name).to_h
    when 'team' then @account.teams.pluck(:id, :name).to_h
    when 'inbox'
      inboxes = @account.inboxes.includes(:channel).to_a
      name_map = inboxes.to_h { |inbox| [inbox.id, inbox.name] }
      name_map[:channels] = inboxes.to_h { |inbox| [inbox.id, inbox.channel&.name] }
      name_map
    else {}
    end
  end

  # ======================= Helpers compartilhados =======================
  def builder_params(extra = {})
    { since: @filters[:since], until: @filters[:until],
      inbox_id: @filters[:inbox_id], business_hours: business_hours? }.merge(extra)
  end

  def business_hours?
    ActiveModel::Type::Boolean.new.cast(@filters[:business_hours])
  end

  # ---- Series temporais / heatmaps (reusam V2::ReportBuilder — so re-bucketizam) ----
  # Trio de tendencias no nivel da conta para o periodo: conversas, FRT, resolucao.
  def account_trends
    return {} if range.blank?

    # Serie toda zerada (periodo sem conversa) nao vira grafico: so mostraria uma linha no chao.
    {
      conversations: count_series('conversations_count'),
      first_response: count_series('avg_first_response_time'),
      resolution: count_series('avg_resolution_time')
    }.select { |_, points| points.any? { |point| point[:value].positive? } }
  end

  def count_series(metric)
    series_points(report_builder_series(metric, ts_group_by))
  end

  def series_points(raw)
    Array(raw).map do |point|
      { label: Time.zone.at(point[:timestamp]).in_time_zone(TZ).strftime('%d/%m'),
        value: point[:value].to_f.round }
    end
  end

  # Matriz dia-da-semana (Seg..Dom) x hora (0..23) a partir da serie por hora.
  # since/until_at permitem janela propria (ex.: overview e snapshot sem range).
  def weekday_hour_heatmap(metric, since: @filters[:since], until_at: @filters[:until])
    matrix = Array.new(7) { Array.new(24, 0) }
    report_builder_series(metric, 'hour', since: since, until_at: until_at).each do |point|
      time = Time.zone.at(point[:timestamp]).in_time_zone(TZ)
      matrix[time.wday][time.hour] += point[:value].to_i
    end
    { day_labels: WEEKDAY_LABELS, values: WEEKDAY_ORDER.map { |i| matrix[i] } }
  end

  def report_builder_series(metric, group_by, since: @filters[:since], until_at: @filters[:until])
    return [] if since.blank? || until_at.blank? || since.to_i.zero? || until_at.to_i.zero?

    V2::Reports::Conversations::ReportBuilder.new(
      @account, { type: :account, metric: metric, group_by: group_by,
                  since: since, until: until_at, inbox_id: @filters[:inbox_id],
                  timezone_offset: TZ_OFFSET }
    ).timeseries
  rescue StandardError => e
    Rails.logger.warn("[report_pdf] serie #{metric}/#{group_by} indisponivel: #{e.message}")
    []
  end

  # Janela padrao de 30 dias para relatorios snapshot (overview) que nao tem range.
  def trailing_window
    { since: 30.days.ago.to_i.to_s, until_at: Time.current.to_i.to_s }
  end

  # Dia para faixas curtas, semana para periodos longos — evita centenas de barras.
  def ts_group_by
    return 'day' if range.blank?

    ((range.last - range.first) / 1.day).to_i > 70 ? 'week' : 'day'
  end

  def avg_metric(rows, key)
    values = rows.filter_map { |row| row[key] }.map(&:to_f).reject(&:zero?)
    values.empty? ? 0 : (values.sum / values.size).round
  end

  # Sem tempo medido mostra "--", como na tela (o "N/A" do presenter e o do CSV).
  def format_seconds(seconds)
    seconds.to_i.positive? ? Reports::TimeFormatPresenter.new(seconds).format : '--'
  end

  def entity_name(id, names)
    return 'Sem atribuição' if id.nil?

    names[id] || "##{id}"
  end

  def agent_names(ids)
    return {} if ids.empty?

    User.where(id: ids).pluck(:id, :name).to_h
  end

  def agent_names_all
    @account.users.pluck(:id, :name).to_h
  end

  def team_names_all
    @account.teams.pluck(:id, :name).to_h
  end

  def pct(part, whole)
    return 0.0 if whole.to_i.zero?

    ((part.to_f / whole) * 100).round(1)
  end

  def period_meta
    { since: format_date(range&.first), until: format_date(range&.last), label: period_label }
  end

  # Nome da caixa quando o relatorio esta recortado por numero — entra no subtitulo
  # para nao circular PDF "de vendas" com numero da conta inteira.
  def inbox_scope_label
    return nil if @filters[:inbox_id].blank?

    @inbox_scope_label ||= @account.inboxes.find_by(id: @filters[:inbox_id])&.name
  end

  def with_inbox_scope(subtitle)
    return subtitle if inbox_scope_label.blank?

    "#{subtitle} · Somente #{inbox_scope_label}"
  end

  def snapshot_period
    { label: "Situação em #{Time.current.in_time_zone(TZ).strftime('%d/%m/%Y %H:%M')}" }
  end

  def period_label
    return 'Todo o período' if range.blank?

    "#{format_date(range.first)} – #{format_date(range.last)}"
  end

  def format_date(value)
    return nil if value.blank?

    time = value.is_a?(Numeric) ? Time.zone.at(value.to_i) : value
    time.in_time_zone(TZ).strftime('%d/%m/%Y')
  end

  def range
    @range ||= begin
      since = @filters[:since]
      until_param = @filters[:until]
      if since.blank? || until_param.blank? || since.to_i.zero? || until_param.to_i.zero?
        nil
      else
        Time.zone.at(since.to_i)...Time.zone.at(until_param.to_i)
      end
    end
  end
end
