# frozen_string_literal: true

# Uma linha por dia da semana de uma unidade. O formato copia `WorkingHour` de
# propósito — mesmas colunas, mesma semântica de open_all_day/closed_all_day — para
# que o editor de horário do front seja o mesmo, e para quem conhece a tela da caixa
# de entrada reconhecer esta.
#
# Diferença que importa: aqui NÃO existe `open_now?`. Este horário é informativo, e
# quem responde "aberta agora" é o front, com o fuso da unidade. Não há consumidor de
# runtime no backend — de propósito.
class UnitWorkingHour < ApplicationRecord
  belongs_to :unit

  before_validation :normalizar_dia_inteiro

  validates :day_of_week, presence: true, inclusion: { in: Unit::DIAS_DA_SEMANA },
                          uniqueness: { scope: :unit_id }

  with_options unless: :closed_all_day? do
    validates :open_hour, :close_hour, presence: true, inclusion: 0..23
    validates :open_minutes, :close_minutes, presence: true, inclusion: 0..59
    validate :fechar_depois_de_abrir
  end

  validate :nao_pode_abrir_e_fechar_o_dia_todo

  private

  def normalizar_dia_inteiro
    return unless open_all_day?

    self.open_hour = 0
    self.open_minutes = 0
    self.close_hour = 23
    self.close_minutes = 59
  end

  # Mesma regra da caixa de entrada: faixa que cruza a meia-noite não é suportada.
  def fechar_depois_de_abrir
    return if [open_hour, open_minutes, close_hour, close_minutes].any?(&:nil?)
    return if open_hour.hours + open_minutes.minutes < close_hour.hours + close_minutes.minutes

    errors.add(:close_hour, I18n.t('errors.units.close_before_open'))
  end

  def nao_pode_abrir_e_fechar_o_dia_todo
    return unless open_all_day? && closed_all_day?

    errors.add(:base, I18n.t('errors.units.open_and_closed'))
  end
end
