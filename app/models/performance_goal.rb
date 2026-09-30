# CHAT-177: meta mensal de um atendente (target_type 'user') ou de um time ('team') num dos quatro
# indicadores. Chama-se PerformanceGoal, nunca Meta: neste repositorio "Meta" e o Facebook.
#
# Validade: a meta gravada em um mes vale dali em diante, ate ser alterada (ninguem redigita todo mes).
# `value` nulo grava "sem meta deste mes em diante". `target_id` nao tem FK (aponta para usuario OU time):
# quem lista parte de usuarios/times que existem, e meta sem alvo simplesmente nao aparece.
class PerformanceGoal < ApplicationRecord
  METRICS = %w[resolved_conversations first_response_time nps kanban_wins].freeze
  TARGET_TYPES = %w[user team].freeze
  # Indicador em que MENOR e melhor.
  LOWER_IS_BETTER = %w[first_response_time].freeze

  belongs_to :account

  validates :month, :target_type, :target_id, :metric, presence: true
  validates :metric, inclusion: { in: METRICS }
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :metric, uniqueness: { scope: [:account_id, :month, :target_type, :target_id] }
  validate :value_in_range, if: -> { value.present? }

  before_validation -> { self.month = month.beginning_of_month if month }

  # { [target_type, target_id, metric] => { value:, since_month: } } com a meta EM VIGOR no mes: a mais
  # recente cujo inicio seja <= mes. Uma consulta so (DISTINCT ON), valores nulos incluidos ("sem meta").
  def self.in_force(account, month)
    rows = where(account: account).where('month <= ?', month.beginning_of_month)
                                  .select('DISTINCT ON (target_type, target_id, metric) *')
                                  .order(:target_type, :target_id, :metric, month: :desc)
    rows.each_with_object({}) do |goal, acc|
      next if goal.value.nil?

      acc[[goal.target_type, goal.target_id, goal.metric]] = { value: goal.value.to_f, since_month: goal.month }
    end
  end

  private

  # Resolvidas e ganhos: inteiro > 0. Primeira resposta: minutos > 0. NPS: inteiro de 1 a 100.
  def value_in_range
    return errors.add(:value, :greater_than, count: 0) unless value.positive?
    return if metric == 'first_response_time'
    return errors.add(:value, :less_than_or_equal_to, count: 100) if metric == 'nps' && value > 100

    errors.add(:value, :not_an_integer) unless value == value.to_i
  end
end
