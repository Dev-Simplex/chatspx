# Metas e limiares de "semáforo" por métrica, fonte única para resolver + helper.
# Origem dos números: metas operacionais de referência ChatSPX (boas práticas de
# atendimento) — configuráveis. Tempos em SEGUNDOS; taxas em pontos percentuais.
#   lower_better: true  -> menor é melhor (tempos): verde se <= green, amarelo se <= yellow.
#   lower_better: false -> maior é melhor (taxas):  verde se >= green, amarelo se >= yellow.
module Reports::PdfBenchmarks
  BENCHMARKS = {
    first_response: { goal: 300, green: 300, yellow: 900, lower_better: true },     # meta 5 min
    resolution: { goal: 14_400, green: 14_400, yellow: 86_400, lower_better: true }, # meta 4 h
    reply: { goal: 600, green: 600, yellow: 1800, lower_better: true },             # meta 10 min
    resolution_rate: { goal: 80, green: 80, yellow: 60, lower_better: false },      # meta 80%
    csat: { goal: 85, green: 85, yellow: 70, lower_better: false },                 # meta 85% satisfeitos
    nps: { goal: 50, green: 50, yellow: 0, lower_better: false, excellent: 75 },    # meta NPS 50 (>=75 excelência)
    sla_hit_rate: { goal: 95, green: 95, yellow: 85, lower_better: false },         # meta 95% no prazo
    bot_resolution_rate: { goal: 60, green: 60, yellow: 30, lower_better: false },  # meta 60% resolvidas pelo bot
    bot_handoff_rate: { goal: 30, green: 30, yellow: 50, lower_better: true }       # meta <=30% transferidas
  }.freeze

  STATUS = {
    good: { color: '#2dc46f', emoji: '🟢', word: 'bom' },
    warn: { color: '#ffc53d', emoji: '🟡', word: 'atenção' },
    bad: { color: '#e54666', emoji: '🔴', word: 'precisa melhorar' }
  }.freeze

  module_function

  def goal(metric)
    BENCHMARKS.dig(metric, :goal)
  end

  def benchmark(metric)
    BENCHMARKS[metric]
  end

  # Retorna { level:, color:, emoji:, word: } para um valor numa métrica.
  def status(value, metric)
    bench = BENCHMARKS[metric]
    return STATUS[:warn].merge(level: :warn) if bench.nil? || value.nil?

    level = level_for(value.to_f, bench)
    STATUS[level].merge(level: level)
  end

  # Severidade numérica p/ ranking (0 bom .. 2 ruim).
  def severity(level)
    { good: 0, warn: 1, bad: 2 }.fetch(level, 1)
  end

  def level_for(value, bench)
    if bench[:lower_better]
      return :good if value <= bench[:green]
      return :warn if value <= bench[:yellow]
    else
      return :good if value >= bench[:green]
      return :warn if value >= bench[:yellow]
    end
    :bad
  end

  # Zona do NPS na escala −100..+100, derivada dos MESMOS limiares do benchmark
  # (fonte única) — usada pelo PDF (hero, gauge, tabela por atendente) para não
  # rehardcodar 75/50/0 em cada template. Devolve :excellent/:good/:warn/:bad.
  def nps_zone(score)
    bench = BENCHMARKS[:nps]
    return :excellent if score >= bench[:excellent]
    return :good if score >= bench[:green]
    return :warn if score >= bench[:yellow]

    :bad
  end
end
