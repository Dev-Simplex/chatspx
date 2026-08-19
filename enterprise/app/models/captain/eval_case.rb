# Um caso do conjunto de eval de um assistente (bloco 6.02).
#
# O caso é do CLIENTE: ele escreve o que o visitante diz e o que espera que a IA faça.
# `mensagens` são os turnos do visitante; `expectativas` usa o vocabulário fechado de
# Captain::Eval::Expectations — fechado de propósito, porque expectativa em texto livre
# só pode ser julgada por outro LLM, e aí o número volta a ser opinião.
class Captain::EvalCase < ApplicationRecord
  self.table_name = 'captain_eval_cases'

  belongs_to :account
  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  has_many :results, class_name: 'Captain::EvalCaseResult',
                     inverse_of: :eval_case, dependent: :destroy

  validates :titulo, presence: true
  validate :mensagens_precisam_de_um_turno
  validate :expectativas_no_vocabulario

  scope :ativos, -> { where(ativo: true) }
  scope :ordenados, -> { order(:posicao, :id) }

  # O texto que o visitante manda, na ordem.
  def turnos
    Array(mensagens).filter_map { |m| m.is_a?(Hash) ? m['content'].presence : m.to_s.presence }
  end

  private

  def mensagens_precisam_de_um_turno
    errors.add(:mensagens, 'precisa de pelo menos um turno do visitante') if turnos.empty?
  end

  def expectativas_no_vocabulario
    erros = Captain::Eval::Expectations.validate(expectativas)
    erros.each { |e| errors.add(:expectativas, e) }
  end
end
