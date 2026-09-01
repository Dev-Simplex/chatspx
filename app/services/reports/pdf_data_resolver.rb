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
      kpis: kpis,
      verdict: nps_verdict(calc),
      distribution: nps_distribution(responded),
      agents: nps_by_agent(responded)
    }
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
    base = "Net Promoter Score de #{kpis[:nps_score]} apurado sobre #{kpis[:total]} avaliações válidas no período."
    return base if kpis[:delta].nil? || kpis[:delta].zero?

    arrow = kpis[:delta].positive? ? '▲' : '▼'
    "#{base} #{arrow} #{kpis[:delta].abs} pts vs período anterior."
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
      subtitle: "Índice de satisfação de #{kpis[:satisfaction]}% (notas 4 e 5) sobre #{total} respostas no período.",
      base_label: "#{total} respostas",
      kpis: kpis,
      verdict: metric_verdict(metric: :csat, value: kpis[:satisfaction], human: "#{kpis[:satisfaction]}%", label: 'Satisfação'),
      distribution: csat_distribution(by_rating),
      feedbacks: csat_feedbacks(scope),
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
    @csat_scope ||= begin
      scope = @account.csat_survey_responses.includes(:contact, :assigned_agent)
      scope = scope.filter_by_created_at(range) if range.present?
      scope = scope.filter_by_assigned_agent_id(@filters[:user_ids])
      scope = scope.filter_by_inbox_id(@filters[:inbox_id])
      scope = scope.filter_by_team_id(@filters[:team_id])
      scope.filter_by_rating(@filters[:rating])
    end
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
      report_type: 'bot', title: 'Relatório do Bot', period: period_meta,
      overline: 'Automação · Confidencial',
      subtitle: "Taxa de resolução automática de #{metrics[:resolution_rate]}% em #{metrics[:conversation_count]} conversas atendidas pelo bot.",
      base_label: "#{metrics[:conversation_count]} conversas",
      kpis: bot_kpis(metrics),
      verdict: bot_verdict(metrics, :bot_resolution_rate, metrics[:resolution_rate], 'Resolução pelo bot'),
      verdict_secondary: bot_verdict(metrics, :bot_handoff_rate, metrics[:handoff_rate], 'Transferência do bot'),
      timeseries: {
        resolutions: count_series('bot_resolutions_count'),
        handoffs: count_series('bot_handoffs_count')
      },
      inboxes: bot_by_inbox
    }
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
      highlight: conversations_highlight(signals),
      attention: conversations_attention(signals),
      trends: account_trends,
      heatmap: heatmap,
      heatmap_insight: heatmap_peak_insight(heatmap),
      table: conversations_table(summary)
    }
  end

  def conversations_subtitle(summary)
    with_inbox_scope(
      "#{summary[:conversations_count]} conversas no período · 1ª resposta média de #{format_seconds(summary[:avg_first_response_time])}."
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
    ].map { |signal| signal.merge(status: Reports::PdfBenchmarks.status(signal[:value], signal[:metric]), ratio: signal_ratio(signal)) }
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
    open = @account.conversations.open
    {
      report_type: 'overview', title: 'Relatório de Visão Geral', period: snapshot_period,
      overline: 'Situação Operacional · Confidencial',
      subtitle: "#{open.count} conversas abertas neste instante · #{open.unattended.count} ainda não atendidas.",
      base_label: "#{open.count} conversas abertas",
      kpis: {
        open: open.count, unattended: open.unattended.count,
        unassigned: open.unassigned.count, pending: @account.conversations.pending.count
      },
      traffic_heatmap: weekday_hour_heatmap('conversations_count', **trailing_window),
      resolutions_heatmap: weekday_hour_heatmap('resolutions_count', **trailing_window),
      agents_table: overview_group_table(:assignee_id, agent_names_all, 'Atendente'),
      teams_table: overview_group_table(:team_id, team_names_all, 'Time')
    }
  end

  def overview_group_table(group_key, names, label)
    open = @account.conversations.open
    counts = open.group(group_key).count
    unattended = open.unattended.group(group_key).count
    unassigned = open.unassigned.group(group_key).count
    rows = counts.sort_by { |_, count| -count }.filter_map do |id, count|
      next if id.nil?

      [names[id] || "##{id}", count.to_s, unattended[id].to_i.to_s, unassigned[id].to_i.to_s]
    end
    { columns: [{ label: label }, { label: 'Abertas', align: 'right' },
                { label: 'Não atendidas', align: 'right' }, { label: 'Não atribuídas', align: 'right' }],
      rows: rows }
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
      subtitle: "Hit rate de #{hit_rate} sobre #{total} SLAs aplicados · #{missed} descumprimentos no período.",
      base_label: "#{total} SLAs aplicados",
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
                   human: hit_rate, label: 'Cumprimento de SLA')
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
    { columns: [{ label: 'Conversa' }, { label: 'Política' }, { label: 'Responsável' }, { label: 'Status' }],
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

    "#{pct(total - missed, total)}%"
  end

  def sla_status_label(status)
    { 'missed' => 'Descumprido', 'active_with_misses' => 'Ativo c/ falhas' }[status.to_s] || status.to_s
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
    rows = V2::Reports::AgentAssignmentBuilder.new(account: @account, params: assignment_params).build
    totals = assignment_totals(rows)
    active = rows.count { |row| row[:received_total].to_i.positive? || row[:assigned_to_others].to_i.positive? }
    {
      report_type: 'agent_assignment', title: 'Relatório de Atribuições', period: period_meta,
      overline: 'Distribuição de Atribuições · Confidencial',
      subtitle: assignment_subtitle(totals, active),
      base_label: "#{totals[:received_total]} atribuições",
      kpis: totals.merge(agents: active),
      source_segments: assignment_source_segments(totals),
      received_chart: assignment_received_chart(rows),
      table: assignment_table(rows),
      conclusion: assignment_conclusion(totals, active, rows)
    }
  end

  # "Leitura executiva" (TL;DR) em linguagem simples — totais + composição em % +
  # quem mais recebeu. Nil quando não há atribuições no período.
  def assignment_conclusion(totals, active, rows)
    total = totals[:received_total].to_i
    return nil if total.zero?

    body = "No período, <span class=\"hl\">#{total} atribuições</span> foram distribuídas entre #{active} atendentes: " \
           "#{assignment_pct(totals[:received_manual], total)}% manuais, " \
           "#{assignment_pct(totals[:received_auto], total)}% automáticas (rodízio) e " \
           "#{assignment_pct(totals[:self_assigned], total)}% auto-assumidas."
    { title: 'Leitura executiva', body: body + assignment_top_phrase(rows) }
  end

  def assignment_pct(value, total)
    ((value.to_i * 100.0) / total).round
  end

  def assignment_top_phrase(rows)
    top = rows.select { |row| row[:received_total].to_i.positive? }.max_by { |row| row[:received_total].to_i }
    return '' if top.nil?

    name = ERB::Util.html_escape(top[:name].presence || "##{top[:id]}")
    " Quem mais recebeu foi <span class=\"hl\">#{name}</span> (#{top[:received_total]})."
  end

  def assignment_params
    { since: @filters[:since], until: @filters[:until],
      team_id: @filters[:team_id], inbox_id: @filters[:inbox_id] }
  end

  def assignment_totals(rows)
    {
      received_total: rows.sum { |row| row[:received_total].to_i },
      received_manual: rows.sum { |row| row[:received_manual].to_i },
      received_auto: rows.sum { |row| row[:received_auto].to_i },
      self_assigned: rows.sum { |row| row[:self_assigned].to_i },
      assigned_to_others: rows.sum { |row| row[:assigned_to_others].to_i }
    }
  end

  def assignment_subtitle(totals, active)
    return 'Nenhuma atribuição registrada no período.' if totals[:received_total].zero?

    "#{totals[:received_total]} atribuições no período, distribuídas entre #{active} atendentes."
  end

  # Split da origem das atribuições recebidas p/ a barra de composição. "Outras" cobre
  # automação/bot/api que entram no total mas não nas 3 faixas principais.
  def assignment_source_segments(totals)
    others = totals[:received_total] - totals[:received_manual] - totals[:received_auto] - totals[:self_assigned]
    segments = [
      { label: 'Manuais', value: totals[:received_manual], color: '#2dc46f' },
      { label: 'Automáticas', value: totals[:received_auto], color: '#1f93ff' },
      { label: 'Auto-assumidas', value: totals[:self_assigned], color: '#95de64' }
    ]
    segments << { label: 'Outras', value: others, color: '#bfbfbf' } if others.positive?
    segments
  end

  def assignment_received_chart(rows)
    rows.select { |row| row[:received_total].to_i.positive? }
        .sort_by { |row| -row[:received_total].to_i }
        .first(10)
        .map { |row| { label: assignment_short_name(row[:name]), value: row[:received_total].to_i } }
  end

  def assignment_short_name(name)
    name.to_s.split(/\s+/).first.presence || '—'
  end

  def assignment_table(rows)
    visible = rows.select { |row| row[:received_total].to_i.positive? || row[:assigned_to_others].to_i.positive? }
    visible = rows if visible.empty?
    visible = visible.sort_by { |row| -row[:received_total].to_i }
    { columns: assignment_columns, rows: visible.map { |row| assignment_row(row) } }
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
    noun = SUMMARY_TITLES[metric_type].sub('Relatório de ', '').downcase
    {
      report_type: metric_type, title: SUMMARY_TITLES[metric_type], period: period_meta,
      overline: 'Desempenho · Confidencial',
      subtitle: with_inbox_scope("#{kpis[:entities]} #{noun} com atividade · #{kpis[:conversations]} conversas no período."),
      base_label: "#{kpis[:conversations]} conversas",
      kpis: kpis,
      highlight: signals.any? ? conversations_highlight(signals) : nil,
      attention: signals.any? ? conversations_attention(signals) : nil,
      trends: metric_type == 'label' ? {} : account_trends,
      table: summary_table(rows, metric_type)
    }
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
    {
      entities: with_data.size,
      conversations: rows.sum { |row| row[:conversations_count].to_i },
      resolved: rows.sum { |row| row[:resolved_conversations_count].to_i },
      avg_first_response: format_seconds(avg_metric(with_data, :avg_first_response_time)),
      avg_resolution: format_seconds(avg_metric(with_data, :avg_resolution_time))
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

    {
      conversations: count_series('conversations_count'),
      first_response: count_series('avg_first_response_time'),
      resolution: count_series('avg_resolution_time')
    }
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

  def format_seconds(seconds)
    Reports::TimeFormatPresenter.new(seconds).format
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
