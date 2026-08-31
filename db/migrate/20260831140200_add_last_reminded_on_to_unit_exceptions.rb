class AddLastRemindedOnToUnitExceptions < ActiveRecord::Migration[7.1]
  # Guarda a data JÁ avisada: o job pode rodar duas vezes no dia (ou alguém rodar à
  # mão) sem mandar o mesmo aviso de novo.
  def change
    add_column :unit_exceptions, :last_reminded_on, :date
  end
end
