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
    Reports::SignalSet.new(entries: entries, benchmarks: benchmarks).build
  end

  private

  attr_reader :summary, :previous, :benchmarks

  # Traduz o summary de Conversas em entradas {metric, value, prev} para o SignalSet.
  def entries
    METRICS.map do |config|
      {
        metric: config[:metric],
        value: value_for(config, summary),
        prev: previous.present? ? value_for(config, previous) : nil
      }
    end
  end

  def normalize(hash)
    return {} if hash.nil?

    hash.respond_to?(:with_indifferent_access) ? hash.with_indifferent_access : hash.to_h.with_indifferent_access
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
end
