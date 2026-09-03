# Uma execução do conjunto de casos (bloco 6.02).
#
# Guarda a IDENTIDADE do prompt que estava valendo (fingerprint + snapshot). É isso que
# permite responder "quantos casos regrediram?" — sem a identidade, duas execuções são
# duas fotos sem legenda.
class Captain::EvalRun < ApplicationRecord
  self.table_name = 'captain_eval_runs'

  STATUSES = %w[pendente rodando concluida erro].freeze

  belongs_to :account
  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  has_many :results, class_name: 'Captain::EvalCaseResult',
                     inverse_of: :eval_run, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  scope :recentes, -> { order(created_at: :desc) }
  scope :concluidas, -> { where(status: 'concluida') }

  def concluida?
    status == 'concluida'
  end

  # Percentual de casos aprovados — o número que a tela mostra grande.
  def aprovacao
    return nil if casos_total.zero?

    (casos_ok.to_f / casos_total * 100).round(1)
  end
end
