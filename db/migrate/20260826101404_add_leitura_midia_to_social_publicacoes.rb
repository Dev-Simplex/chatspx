# O que está ESCRITO nas imagens da publicação, em texto.
#
# Motivo, direto do teste ao vivo de 26/08: a IA respondeu "consulte o preço no direct" a uma
# pergunta de preço cuja resposta estava, literalmente, nas imagens do carrossel do próprio post.
# A legenda não traz preço; o encarte traz. Sem ler a imagem, a IA é obrigada a mandar embora
# quem já estava olhando a resposta.
#
# Guardado NA PUBLICAÇÃO, e não por comentário, porque o encarte é o mesmo para todo mundo que
# comenta ali: lê-se uma vez, responde-se muitas.
class AddLeituraMidiaToSocialPublicacoes < ActiveRecord::Migration[7.1]
  def change
    add_column :social_publicacoes, :leitura_midia, :text, if_not_exists: true
    # Quando a leitura foi feita. Nulo = ninguém leu ainda, que é diferente de "leu e não achou
    # nada" — a mesma distinção entre ausência e falha que vale no resto deste módulo.
    add_column :social_publicacoes, :lida_em, :datetime, if_not_exists: true
  end
end
