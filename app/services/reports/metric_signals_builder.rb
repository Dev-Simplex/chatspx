# Constrói os "sinais" estruturados (semáforo) das métricas de Conversas a partir do
# summary do relatório. É a fonte única do VEREDITO (level/ratio/highlight/attention),
# compartilhada entre a geração de PDF e o endpoint da API.
#
# IMPORTANTE: este serviço NÃO devolve texto traduzido. Ele devolve apenas o veredito
# estruturado; a frase em linguagem natural é montada no frontend via i18n.
#
# Saída de `build` → Array<Hash> no contrato:
#   { metric:, value:, goal:, level:, ratio:, delta_pct:, is_highlight:, is_attention: }
class Reports::MetricSignalsBuilder
  # Métricas avaliáveis pelo semáforo e como extrair o valor do summary.
  # :time  -> valor cru em segundos, vindo direto da chave do summary.
  # :rate  -> valor calculado (taxa de resolução em pontos percentuais).
  METRICS = [
    { metric: :first_response, key: :avg_first_response_time, kind: :time },
    { metric: :resolution, key: :avg_resolution_time, kind: :time },
    { metric: :reply, key: :reply_time, kind: :time },
    { metric: :resolution_rate, key: nil, kind: :rate }
  ].freeze

  def initialize(summary:, previous: nil, benchmarks: Reports::PdfBenchmarks::BENCHMARKS)
    @summary = normalize(summary)
    @previous = normalize(previous)
    @benchmarks = benchmarks
  end

  def build
    signals = METRICS.filter_map { |config| signal_for(config) }
    mark_highlight_and_attention(signals)
    signals.map { |signal| present(signal) }
  end

  private

  attr_reader :summary, :previous, :benchmarks

  def normalize(hash)
    return {} if hash.nil?

    hash.respond_to?(:with_indifferent_access) ? hash.with_indifferent_access : hash.to_h.with_indifferent_access
  end

  def signal_for(config)
    metric = config[:metric]
    bench = benchmarks[metric]
    return nil if bench.nil?

    value = value_for(config, summary)
    prev = previous.present? ? value_for(config, previous) : nil
    level = Reports::PdfBenchmarks.level_for(value, bench)

    {
      metric: metric,
      kind: config[:kind],
      value: value,
      goal: bench[:goal],
      level: level,
      ratio: ratio_for(config[:kind], value, bench[:goal]),
      delta_pct: delta_pct_for(value, prev),
      severity: Reports::PdfBenchmarks.severity(level)
    }
  end

  def value_for(config, source)
    return resolution_rate(source) if config[:kind] == :rate

    source[config[:key]].to_f
  end

  # Taxa de resolução em pontos percentuais (mesma fórmula do resolver de PDF).
  def resolution_rate(source)
    total = source[:conversations_count].to_i
    return 0 if total.zero?

    ((source[:resolutions_count].to_f / total) * 100).round.clamp(0, 100)
  end

  # Razão vs meta, normalizada para "menor = melhor" nas duas direções (mesma lógica do PDF).
  def ratio_for(kind, value, goal)
    goal = goal.to_f
    return 99.0 if goal.zero?

    raw = kind == :rate ? goal / [value, 1].max : value / goal
    raw.round(2)
  end

  def delta_pct_for(value, prev)
    return nil if prev.nil? || prev.zero?

    (((value - prev) / prev) * 100).round
  end

  # Marca exatamente um highlight (melhor sinal) e, se houver algo fora do verde,
  # um attention (pior sinal). Ordena por severidade e desempata por ratio.
  def mark_highlight_and_attention(signals)
    return if signals.empty?

    best = signals.min_by { |signal| [signal[:severity], signal[:ratio]] }
    worst = signals.max_by { |signal| [signal[:severity], signal[:ratio]] }

    best[:is_highlight] = true
    worst[:is_attention] = true if worst[:level] != :good
  end

  def present(signal)
    {
      metric: signal[:metric].to_s,
      value: signal[:value],
      goal: signal[:goal],
      level: signal[:level].to_s,
      ratio: signal[:ratio],
      delta_pct: signal[:delta_pct],
      is_highlight: signal.fetch(:is_highlight, false),
      is_attention: signal.fetch(:is_attention, false)
    }
  end
end
