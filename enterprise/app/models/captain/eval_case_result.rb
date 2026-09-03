# O veredito de UM caso em UMA execução (bloco 6.02).
class Captain::EvalCaseResult < ApplicationRecord
  self.table_name = 'captain_eval_case_results'

  belongs_to :account
  belongs_to :eval_run, class_name: 'Captain::EvalRun'
  belongs_to :eval_case, class_name: 'Captain::EvalCase'

  scope :falhas, -> { where(passou: false) }
end
