# frozen_string_literal: true

# Exceção de data de uma unidade — o feriado, que não existe em lugar nenhum do
# sistema hoje (`working_hours` é grade semanal pura, sem coluna de data).
#
# Ou fecha o dia (`closed_all_day`, o caso comum), ou substitui o horário daquele dia
# (véspera que fecha mais cedo). `annual` cobre feriado de data fixa — 25/12 vale para
# todo ano sem recadastro; a comparação por dia/mês é feita por quem lê.
class UnitException < ApplicationRecord
  belongs_to :unit

  validates :name, presence: true
  validates :date, presence: true, uniqueness: { scope: :unit_id }

  with_options unless: :closed_all_day? do
    validates :open_hour, :close_hour, presence: true, inclusion: 0..23
    validates :open_minutes, :close_minutes, presence: true, inclusion: 0..59
  end
end
