# frozen_string_literal: true

# Quem a conta já respondeu, por publicação.
#
# ⚠️ ISTO É INFERÊNCIA, NÃO DADO. O webhook de comentário do Instagram **não traz `parent_id`**:
# a resposta da conta chega como um comentário comum na mesma publicação. O que a liga a alguém
# é a convenção — o time começa a resposta com `@usuario`, e foi assim em todas as respostas
# medidas na conta da BigStore em 24/08 (`@lallis46 oie, sim`, `@cauani_gomes oie, bom dia`...).
#
# Por isso "respondido" é marcado como derivado na tela, e não afirmado como fato. O conserto
# durável é buscar `parent_id` na Graph ao gravar o comentário; enquanto isso não existe, esta
# heurística é a diferença entre a tela ser uma lista passiva e responder à única pergunta que
# o operador realmente faz — "o que ainda falta responder?".
#
# Falso negativo (resposta sem @) mostra como não respondido: erra para o lado de sobrar
# trabalho na tela, não para o lado de esconder cliente sem resposta.
class Spx::Social::Respondidos
  # Um ou mais @handles no COMEÇO do texto. Menção no meio da frase não é endereçamento — é
  # citação, e tratá-la como resposta marcaria gente que ninguém respondeu.
  MENCOES_INICIAIS = /\A(?:\s*@([A-Za-z0-9._]+))+/

  def initialize(comentarios)
    @respondidos = Set.new

    comentarios.each do |comentario|
      next unless comentario.proprio?

      handles(comentario.texto).each do |handle|
        @respondidos << chave(comentario.publicacao_external_id, handle)
      end
    end
  end

  def respondido?(comentario)
    return false if comentario.proprio?
    return false if comentario.autor_username.blank?

    @respondidos.include?(chave(comentario.publicacao_external_id, comentario.autor_username))
  end

  private

  def handles(texto)
    trecho = texto.to_s[MENCOES_INICIAIS]
    return [] if trecho.blank?

    trecho.scan(/@([A-Za-z0-9._]+)/).flatten.map(&:downcase)
  end

  def chave(publicacao_external_id, handle)
    "#{publicacao_external_id}|#{handle.to_s.downcase}"
  end
end
