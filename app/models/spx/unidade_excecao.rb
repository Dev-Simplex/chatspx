# Exceção DATADA de funcionamento — a camada que muda toda semana, e a razão de existir do
# contrato: ela tem data e morre sozinha. Ninguém precisa lembrar de desfazer nada.
#
# O alcance é escolhido por qual campo vem preenchido:
#   unidade_id  → uma unidade
#   etiqueta    → todas as unidades que carregam a etiqueta (campanha nunca é uma loja só)
#   nenhum dos dois → a conta inteira (feriado nacional)
class Spx::UnidadeExcecao < ApplicationRecord
  self.table_name = 'unidade_excecoes'

  belongs_to :account
  belongs_to :unidade, class_name: 'Spx::Unidade', optional: true, inverse_of: :excecoes

  validates :data_inicio, presence: true
  validates :data_fim, presence: true
  validate :fim_nao_anterior_ao_inicio

  before_validation :normalizar_etiqueta

  scope :vigentes_em, ->(data) { where('data_inicio <= :dia AND data_fim >= :dia', dia: data) }
  scope :vigentes_entre, lambda { |inicio, fim|
    where('data_inicio <= :fim AND data_fim >= :inicio', inicio: inicio, fim: fim)
  }
  scope :a_partir_de, ->(data) { where(arel_table[:data_fim].gteq(data)) }

  def vigente_em?(data)
    data_inicio.present? && data_fim.present? && data >= data_inicio && data <= data_fim
  end

  # "Mais específico vence." Unidade pesa mais que etiqueta, e etiqueta mais que conta inteira.
  # Somar os dois faz uma exceção que nomeia unidade E etiqueta ganhar de uma que só nomeia a
  # unidade — o que é coerente com a regra, mesmo sendo um caso que a carga não produz.
  def especificidade
    (unidade_id.present? ? 2 : 0) + (etiqueta.present? ? 1 : 0)
  end

  def aplica_a?(alvo)
    return false unless account_id == alvo.account_id
    return false if unidade_id.present? && unidade_id != alvo.id
    return false if etiqueta.present? && !alvo.etiqueta?(etiqueta)

    true
  end

  def faixa
    Spx::Unidade.faixa(fechada: fechada?, abre: abre, fecha: fecha)
  end

  private

  def normalizar_etiqueta
    self.etiqueta = Spx::Unidade.normalizar(etiqueta) if etiqueta.present?
  end

  def fim_nao_anterior_ao_inicio
    return if data_inicio.blank? || data_fim.blank?
    return if data_fim >= data_inicio

    errors.add(:data_fim, 'não pode ser anterior a data_inicio')
  end
end
