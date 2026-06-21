# Núcleo genérico do "semáforo" de relatórios. Recebe uma lista de métricas já
# resolvidas (metric + value [+ prev]) e devolve os sinais estruturados no
# contrato compartilhado entre PDF e API:
#   { metric:, value:, goal:, level:, ratio:, delta_pct:, is_highlight:, is_attention: }
#
# É a fonte única do VEREDITO (level/ratio/highlight/attention), reaproveitada por
# Conversas (via Reports::MetricSignalsBuilder), CSAT e NPS. Reusa Reports::PdfBenchmarks
# para a regra de benchmark — não duplica thresholds.
#
# NÃO devolve texto traduzido: a frase em linguagem natural é montada no frontend
# (web) ou nos templates (PDF).
class Reports::SignalSet
  # entries: Array<Hash> com { metric:, value:, prev: (opcional) }.
  #   - metric: símbolo/strings presente em `benchmarks`
  #   - value:  valor cru (mantido como veio no output; segundos, % ou score)
  #   - prev:   valor do período anterior (nil quando indisponível)
  def initialize(entries:, benchmarks: Reports::PdfBenchmarks::BENCHMARKS)
    @entries = entries || []
    @benchmarks = benchmarks
  end

  def build
    signals = @entries.filter_map { |entry| signal_for(entry) }
    mark_highlight_and_attention(signals)
    signals.map { |signal| present(signal) }
  end

  private

  attr_reader :benchmarks

  def signal_for(entry)
    metric = entry[:metric].to_sym
    bench = benchmarks[metric]
    return nil if bench.nil?

    value = entry[:value]
    level = Reports::PdfBenchmarks.level_for(value.to_f, bench)
    {
      metric: metric,
      value: value,
      goal: bench[:goal],
      level: level,
      ratio: ratio_for(bench, value.to_f),
      delta_pct: delta_pct_for(value, entry[:prev]),
      severity: Reports::PdfBenchmarks.severity(level)
    }
  end

  # Razão vs meta, normalizada para "menor = melhor" nas duas direções.
  # lower_better (tempos): value/goal · senão (taxas/scores): goal/[value,1].max.
  def ratio_for(bench, value)
    goal = bench[:goal].to_f
    return 99.0 if goal.zero?

    raw = bench[:lower_better] ? value / goal : goal / [value, 1].max
    raw.round(2)
  end

  def delta_pct_for(value, prev)
    return nil if prev.nil? || prev.to_f.zero?

    (((value.to_f - prev.to_f) / prev.to_f) * 100).round
  end

  # Marca exatamente um highlight (melhor) e, se houver algo fora do verde,
  # um attention (pior). Ordena por severidade e desempata por ratio.
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
