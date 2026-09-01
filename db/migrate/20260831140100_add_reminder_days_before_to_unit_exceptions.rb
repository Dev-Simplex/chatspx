class AddReminderDaysBeforeToUnitExceptions < ActiveRecord::Migration[7.1]
  # Dias, não minutos: feriado de filial se prepara com antecedência. nil = sem aviso.
  def change
    add_column :unit_exceptions, :reminder_days_before, :integer
  end
end
