# Coordenada da unidade, para a tela poder guardar o pin que hoje só existia na implementação
# irmã (`unidades`), agora aposentada.
#
# `decimal(10,6)` como a migration de `unidades` (20260901193446): seis casas são ~11 cm, que é
# mais precisão do que qualquer loja precisa, e decimal não tem o arredondamento binário do float
# — coordenada é dado de cadastro, não de cálculo científico.
#
# `if_not_exists` porque a frota é migrada VM a VM e uma delas pode já ter recebido a coluna.
class AddCoordenadasToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :latitude, :decimal, precision: 10, scale: 6, if_not_exists: true
    add_column :units, :longitude, :decimal, precision: 10, scale: 6, if_not_exists: true
  end
end
