# frozen_string_literal: true

# Bloco 1.22 — relatório mínimo de origem: conversas por `utm_source`/`utm_medium`/`utm_campaign`
# no período, mais a classificação do 1.19.
#
# Duas regras deste relatório existem para ele NÃO mentir:
#
#   1. Conversa sem origem sai com `value: nil` — o front a rotula "origem não disponível".
#      Nunca "origem direta": não sabemos que o acesso foi direto, sabemos que não recebemos dado.
#   2. O período anterior à entrada da medição sai contado em `before_measurement`, **nunca
#      vazio nem zerado**. Zero é lido como "não veio ninguém", e isso é mentira: veio gente, só
#      não havia quem anotasse de onde.
#
# O marco da medição é o `created_at` da definição `last_origin_kind` da conta — ela nasce exatamente
# quando o 1.18 provisiona a conta, seja pela rake do deploy ou pela primeira conversa com origem.
# Sem estado novo e sem configuração que alguém possa esquecer de preencher.
class Tracking::OriginReport
  GROUPINGS = {
    source: 'last_utm_source',
    medium: 'last_utm_medium',
    campaign: 'last_utm_campaign',
    origin_kind: 'last_origin_kind'
  }.freeze

  MAX_ROWS = 50

  def initialize(account:, since:, until_time:)
    @account = account
    @since = since
    @until_time = until_time
  end

  def perform
    {
      measurement_started_at: measurement_started_at,
      range: { since: since, until: until_time },
      before_measurement: {
        conversations_count: before_measurement_scope.count,
        covers_whole_range: measurement_started_at.blank? || measurement_started_at >= until_time
      },
      measured: measured_payload
    }
  end

  private

  attr_reader :account, :since, :until_time

  def measurement_started_at
    return @measurement_started_at if defined?(@measurement_started_at)

    @measurement_started_at = account.custom_attribute_definitions
                                     .find_by(attribute_key: 'last_origin_kind', attribute_model: 'conversation_attribute')
                                     &.created_at
  end

  def range_scope
    account.conversations.where(created_at: since..until_time)
  end

  # Conversas do período que nasceram ANTES de a medição existir. Elas não têm origem porque
  # ninguém a coletava — não porque o visitante não tinha origem.
  def before_measurement_scope
    return range_scope if measurement_started_at.blank?

    range_scope.where(conversations: { created_at: ...measurement_started_at })
  end

  def measured_scope
    return account.conversations.none if measurement_started_at.blank?

    range_scope.where(conversations: { created_at: measurement_started_at.. })
  end

  def measured_payload
    scope = measured_scope

    GROUPINGS.transform_values { |key| grouped_counts(scope, key) }
             .merge(conversations_count: scope.count)
  end

  # `value: nil` é a conversa medida que não trouxe aquele parâmetro. Ela conta — some daria um
  # total que não fecha com o número de conversas, e o cliente perderia a noção de cobertura.
  def grouped_counts(scope, attribute_key)
    scope.group(Arel.sql("custom_attributes ->> #{ActiveRecord::Base.connection.quote(attribute_key)}"))
         .order(Arel.sql('count_all DESC'))
         .limit(MAX_ROWS)
         .count
         .map { |value, count| { value: value.presence, count: count } }
  end
end
