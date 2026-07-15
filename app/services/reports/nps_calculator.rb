# Fonte ÚNICA do cálculo de NPS dos relatórios. Substitui as três cópias
# divergentes que existiam (controller, metrics.json.jbuilder e o PDF resolver),
# que já discordavam entre si (a API arredondava cada percentual e devolvia
# decimal; o PDF fazia o cálculo padrão em um passo e devolvia inteiro).
#
# Regras (padrão de mercado do NPS):
#   - score: %promotores − %detratores, em UM passo, arredondado para INTEIRO
#     na escala −100..+100.
#   - taxa de resposta: numerador (respostas confiáveis) e denominador
#     (pesquisas enviadas) saem do MESMO coorte/filtros e o resultado é
#     clampeado em 0..100 (elimina o >100% que a mistura answered_at/created_at
#     produzia).
#   - guarda de amostra: reliable? só é verdadeiro com N >= MIN_SAMPLE — abaixo
#     disso o número é volátil e não deve gerar veredito agressivo.
#   - tendência: delta em PONTOS vs período anterior (percentual não faz sentido
#     numa escala com sinal que cruza o zero).
class Reports::NpsCalculator
  MIN_SAMPLE = 30

  PROMOTER_RANGE = (9..10)
  PASSIVE_RANGE  = (7..8)
  DETRACTOR_RANGE = (0..6)

  # Cálculo puro e reutilizável (unit-testável sem banco). Inteiro, um passo.
  def self.score(promoters:, detractors:, total:)
    total = total.to_i
    return 0 if total.zero?

    (((promoters.to_i - detractors.to_i).to_f / total) * 100).round
  end

  # Deriva o NPS de um {score => contagem} (ex.: relation.group(:score).count).
  def self.score_from_counts(counts)
    promoters = counts.select { |score, _| PROMOTER_RANGE.cover?(score) }.values.sum
    detractors = counts.select { |score, _| DETRACTOR_RANGE.cover?(score) }.values.sum
    total = counts.values.sum
    score(promoters: promoters, detractors: detractors, total: total)
  end

  # responded_scope: relation JÁ escopada a respondidas + score presente +
  #   confiáveis (trusted) do coorte do período.
  # sent_count: nº de pesquisas enviadas (sent/responded/expired) no MESMO
  #   coorte/filtros — denominador da taxa de resposta.
  # previous_score: NPS inteiro do período imediatamente anterior (ou nil).
  def initialize(responded_scope:, sent_count:, previous_score: nil)
    @scores_count = normalize_counts(responded_scope.group(:score).count)
    @promoters  = sum_in(PROMOTER_RANGE)
    @passives   = sum_in(PASSIVE_RANGE)
    @detractors = sum_in(DETRACTOR_RANGE)
    @total      = @promoters + @passives + @detractors
    @sent_count = sent_count.to_i
    @previous_score = previous_score
  end

  attr_reader :promoters, :passives, :detractors, :total, :scores_count, :sent_count

  def score
    self.class.score(promoters: @promoters, detractors: @detractors, total: @total)
  end

  def promoters_pct = pct(@promoters)
  def passives_pct = pct(@passives)
  def detractors_pct = pct(@detractors)

  def response_rate
    return 0.0 if @sent_count.zero?

    [(@total.to_f / @sent_count * 100).round(1), 100.0].min
  end

  # N mínimo para o número ser confiável. Abaixo disso o front mostra selo de
  # "amostra baixa" e o veredito é neutralizado.
  def reliable?
    @total >= MIN_SAMPLE
  end

  # Variação em PONTOS de NPS vs período anterior (nil se não há base anterior).
  def delta
    return nil if @previous_score.nil?

    score - @previous_score
  end

  # Contrato consumido pelo jbuilder (API) e pelo PDF resolver — fonte única.
  def to_h
    {
      nps_score: score,
      total_count: @total,
      sent_count: @sent_count,
      promoters_count: @promoters,
      passives_count: @passives,
      detractors_count: @detractors,
      promoters_pct: promoters_pct,
      passives_pct: passives_pct,
      detractors_pct: detractors_pct,
      response_rate: response_rate,
      reliable: reliable?,
      min_sample: MIN_SAMPLE,
      previous_nps_score: @previous_score,
      nps_delta: delta,
      scores_count: @scores_count
    }
  end

  private

  # Garante chaves Integer (o group(:score) já devolve Integer, mas blinda contra
  # score vindo como string em algum caminho).
  def normalize_counts(counts)
    counts.each_with_object({}) do |(score, count), memo|
      next if score.nil?

      memo[score.to_i] = memo[score.to_i].to_i + count
    end
  end

  def sum_in(range)
    @scores_count.select { |score, _| range.cover?(score) }.values.sum
  end

  def pct(part)
    return 0.0 if @total.zero?

    (part.to_f / @total * 100).round(1)
  end
end
