# As duas colunas que faltavam para a `units` ser destino fiel da `unidades`, aposentada aqui.
#
# `etiquetas` decide exceção por rótulo (uma regra vale para toda unidade marcada "matriz"), e
# `atributos` é o que a IA repete ao cliente — na Tozi guarda o CRECI. Sem elas a unificação
# perderia dado que chega na conversa, e "unificar" viraria "descartar metade".
#
# Mesmo formato e mesmo default da tabela antiga, para a cópia ser literal.
class AddEtiquetasEAtributosToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :etiquetas, :jsonb, default: [], null: false, if_not_exists: true
    add_column :units, :atributos, :jsonb, default: {}, null: false, if_not_exists: true
  end
end
