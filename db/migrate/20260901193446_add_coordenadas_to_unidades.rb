# Coordenada da unidade, para PIN no mapa e para "qual a mais perto de mim".
#
# É dado ESTÁTICO, carregado junto com a unidade — não geocoding em tempo de atendimento. Duas
# razões medidas: a conta da BigStore não tem integração google nenhuma (então não haveria chave
# pra chamar), e o geocoding do Google não diz que não achou — devolve homônimo. Na Tozi, 67 dos
# 259 bairros (26%) caíram a mais de 3 km, um deles a 518 km. Com ~20 lojas, a coordenada se
# confere uma vez, na carga, e depois é aritmética sem rede.
#
# `if_not_exists` porque a migration é aplicada com alvo, VM a VM, e outra frente pode ter tocado
# a mesma tabela num banco de teste compartilhado.
class AddCoordenadasToUnidades < ActiveRecord::Migration[7.1]
  def change
    add_column :unidades, :latitude, :decimal, precision: 10, scale: 6, if_not_exists: true
    add_column :unidades, :longitude, :decimal, precision: 10, scale: 6, if_not_exists: true
  end
end
