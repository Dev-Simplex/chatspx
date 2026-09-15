# frozen_string_literal: true

# Até que ano os feriados nacionais já foram postos no calendário desta unidade.
#
# Sem esta marca o automático brigaria com quem apaga: a filial que abre no Carnaval tiraria
# a linha e o job diário a traria de volta na manhã seguinte. Com ela, o job só gera ANO NOVO
# — o que foi apagado fica apagado.
#
# Nulo = nunca gerado; é assim que a unidade que já existia entra na primeira volta do job.
class AddFeriadosNacionaisAteToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :feriados_nacionais_ate, :integer
  end
end
