# frozen_string_literal: true

# Bloco 5.11 / T-C8.1 — a lista de NOMES de campo do log de auditoria, derivada do payload REAL.
#
# Derivar em vez de declarar e a diferenca entre um log que prova e um log que promete. Uma lista
# escrita a mao ao lado do payload envelhece no primeiro campo acrescentado, e o log passa a dizer
# que `em` nao saiu num dia em que ele saiu. Aqui o log so pode mentir se o payload mentir junto.
#
# Devolve NOMES DE FOLHA, nunca valores, nunca caminhos com valor embutido — e o aceite do 5.12
# depende disso: `field_names` vai para uma tela de suporte, e uma tela de suporte com e-mail de
# visitante e um incidente.
module Tracking::FieldNames
  module_function

  def from(payload)
    collect(payload).uniq.sort
  end

  def collect(node)
    case node
    when Hash  then node.flat_map { |key, value| [key.to_s] + collect(value) }
    when Array then node.flat_map { |item| collect(item) }
    else []
    end
  end
end
