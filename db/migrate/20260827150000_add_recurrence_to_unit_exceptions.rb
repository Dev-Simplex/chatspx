# frozen_string_literal: true

# A exceção de data vira REGRA DE AGENDA.
#
# Até aqui uma exceção *era* uma data: o índice único (unidade, data) amarrava cada
# regra a um dia só, e a única repetição possível era `annual` — mesmo dia, todo ano.
# Ficava de fora justamente o que a operação pede: "abre no 1º e no 3º domingo",
# "férias coletivas de 20/12 a 05/01", "toda segunda de janeiro fecha mais cedo".
#
# O efeito continua sendo `closed_all_day` + a faixa própria: fechar o dia, ou abrir
# em horário especial — e é assim que a regra ABRE um domingo que a grade fecha.
class AddRecurrenceToUnitExceptions < ActiveRecord::Migration[7.1]
  def up
    # Sai antes do rename: o Rails renomeia índices junto com a coluna, e depois o
    # nome não seria mais este.
    remove_index :unit_exceptions, column: [:unit_id, :date]
    rename_column :unit_exceptions, :date, :starts_on

    add_column :unit_exceptions, :ends_on, :date
    add_column :unit_exceptions, :category, :integer, null: false, default: 0
    add_column :unit_exceptions, :frequency, :integer, null: false, default: 0
    add_column :unit_exceptions, :repeat_interval, :integer, null: false, default: 1
    add_column :unit_exceptions, :weekdays, :integer, array: true, null: false, default: []
    add_column :unit_exceptions, :week_positions, :integer, array: true, null: false, default: []
    add_column :unit_exceptions, :month_days, :integer, array: true, null: false, default: []
    add_column :unit_exceptions, :until_date, :date

    # `annual` vira frequência anual (3); todo o resto nasce como "não repete" (0).
    execute 'UPDATE unit_exceptions SET frequency = 3 WHERE annual = true'
    remove_column :unit_exceptions, :annual

    # Índice comum: duas regras podem começar no mesmo dia (uma fecha o dia 10, outra
    # abre o 1º domingo). Quem decide o dia é a precedência, na tela.
    add_index :unit_exceptions, [:unit_id, :starts_on]
  end

  def down
    add_column :unit_exceptions, :annual, :boolean, null: false, default: false
    execute 'UPDATE unit_exceptions SET annual = true WHERE frequency = 3'
    # Regra que repete não cabe no formato antigo: uma data, uma linha.
    execute 'DELETE FROM unit_exceptions WHERE frequency IN (1, 2)'

    remove_index :unit_exceptions, column: [:unit_id, :starts_on]
    remove_column :unit_exceptions, :until_date
    remove_column :unit_exceptions, :month_days
    remove_column :unit_exceptions, :week_positions
    remove_column :unit_exceptions, :weekdays
    remove_column :unit_exceptions, :repeat_interval
    remove_column :unit_exceptions, :frequency
    remove_column :unit_exceptions, :category
    remove_column :unit_exceptions, :ends_on

    rename_column :unit_exceptions, :starts_on, :date
    add_index :unit_exceptions, [:unit_id, :date], unique: true
  end
end
