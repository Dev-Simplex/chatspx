# frozen_string_literal: true

# Regra de agenda de uma unidade: o feriado, o evento, a parada de manutenção, a
# temporada. Ou fecha o dia (`closed_all_day`, o caso comum), ou substitui o horário
# daquele dia — e é assim que uma regra ABRE um domingo que a grade da semana fecha.
#
# A repetição segue o espírito do Google Agenda: semanal, mensal (por dia do mês OU
# por posição do dia da semana — "1º e 3º domingo"), anual, "a cada N". `ends_on` é
# outra coisa: a duração de uma regra que NÃO repete, para o período de férias caber
# numa linha só em vez de dezessete.
#
# Quem avalia a regra é o FRONT (`units/unitSchedule.js`), com o fuso da unidade — não
# há consumidor de runtime no backend, de propósito (ver UnitWorkingHour). Aqui mora
# só o que precisa ser verdade no banco.
class UnitException < ApplicationRecord
  POSICOES_NO_MES = [1, 2, 3, 4, 5, -1].freeze # -1 = última do mês
  DIAS_DO_MES = ((1..31).to_a + [-1]).freeze   # -1 = último dia do mês
  DIAS_DA_SEMANA = (0..6).to_a.freeze

  belongs_to :unit

  enum category: { feriado: 0, evento: 1, manutencao: 2, temporada: 3 }
  enum frequency: { nao_repete: 0, semanal: 1, mensal: 2, anual: 3 }

  validates :name, presence: true
  validates :starts_on, presence: true
  validates :repeat_interval, numericality: { only_integer: true, greater_than: 0 }

  with_options unless: :closed_all_day? do
    validates :open_hour, :close_hour, presence: true, inclusion: 0..23
    validates :open_minutes, :close_minutes, presence: true, inclusion: 0..59
  end

  validate :listas_dentro_do_permitido
  validate :repeticao_completa
  validate :periodo_coerente
  validate :termino_coerente

  private

  def listas_dentro_do_permitido
    errors.add(:weekdays, I18n.t('errors.units.invalid_weekday')) unless (weekdays - DIAS_DA_SEMANA).empty?
    errors.add(:week_positions, I18n.t('errors.units.invalid_week_position')) unless (week_positions - POSICOES_NO_MES).empty?
    errors.add(:month_days, I18n.t('errors.units.invalid_month_day')) unless (month_days - DIAS_DO_MES).empty?
  end

  # Sem isto a regra existiria sem saber quando cai: "repete toda semana" em dia nenhum,
  # "repete todo mês" sem dizer se é pelo dia do mês ou pela posição do dia da semana.
  def repeticao_completa
    errors.add(:base, I18n.t('errors.units.weekday_required')) if semanal? && weekdays.empty?
    return unless mensal? && month_days.empty? && (week_positions.empty? || weekdays.empty?)

    errors.add(:base, I18n.t('errors.units.monthly_rule_required'))
  end

  # Período é a duração de uma regra que não repete; quem repete termina por `until_date`.
  def periodo_coerente
    return if ends_on.blank?

    errors.add(:base, I18n.t('errors.units.range_only_without_repeat')) unless nao_repete?
    errors.add(:ends_on, I18n.t('errors.units.end_before_start')) if starts_on.present? && ends_on < starts_on
  end

  def termino_coerente
    return if until_date.blank? || starts_on.blank? || until_date >= starts_on

    errors.add(:until_date, I18n.t('errors.units.end_before_start'))
  end
end
