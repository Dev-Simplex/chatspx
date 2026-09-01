# frozen_string_literal: true

# A parada para o almoço: o dia abre 08:00, fecha 12:00, volta 13:30 e encerra 18:00.
#
# Aditiva e opcional — as quatro colunas nascem nulas, e dia sem pausa continua
# funcionando exatamente como antes. Uma pausa por dia cobre o caso real (almoço); dois
# turnos partidos no mesmo dia continuariam fora, e isso está anotado de propósito.
#
# NÃO toca em `working_hours` (a grade da caixa de entrada), que alimenta mensagem de
# ausência e widget. Aqui o horário é informativo.
class AddLunchBreakToUnitWorkingHours < ActiveRecord::Migration[7.1]
  def change
    add_column :unit_working_hours, :break_start_hour, :integer
    add_column :unit_working_hours, :break_start_minutes, :integer
    add_column :unit_working_hours, :break_end_hour, :integer
    add_column :unit_working_hours, :break_end_minutes, :integer
  end
end
