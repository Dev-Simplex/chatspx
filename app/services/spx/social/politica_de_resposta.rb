# frozen_string_literal: true

# Quem pode receber resposta, e em que forma. É o portão do piloto.
#
# 🔴 A DECISÃO QUE MAIS IMPORTA AQUI: **lista vazia significa NINGUÉM, nunca "todo mundo".**
# O padrão oposto é o jeito clássico de vazar — alguém liga a chave, esquece de preencher a
# lista, e a conta inteira começa a responder cliente real. Sair do piloto é um ato explícito:
# preencher a lista, ou marcar `todos: true`.
#
# Config por conta, em `account.settings['social_reply']` (mesmo padrão de `contact_invite` e
# `template_reply_routing`):
#
#   {"publica": false, "privada": true, "allowlist": ["pauloseze"], "todos": false}
#
# As duas formas têm chave SEPARADA porque são coisas diferentes para quem está de fora:
# a pública aparece embaixo do post para qualquer cliente; a privada só o autor lê.
class Spx::Social::PoliticaDeResposta
  FORMAS = %w[publica privada].freeze

  pattr_initialize [:account!]

  def permite?(comentario, forma)
    motivo_da_recusa(comentario, forma).nil?
  end

  # Devolve o porquê da recusa, ou nil quando pode. Existe separado do booleano porque a tela
  # precisa DIZER por que não respondeu — "não aconteceu nada" é a pior resposta possível para
  # quem opera, e foi o defeito que este módulo inteiro veio consertar.
  def motivo_da_recusa(comentario, forma)
    return :forma_desconhecida unless FORMAS.include?(forma.to_s)
    return :forma_desligada unless ligada?(forma)
    return :comentario_da_propria_conta if comentario.proprio?
    return :fora_do_piloto unless liberado?(comentario.autor_username)
    return :ja_respondido if comentario.respondido_em?(forma)

    nil
  end

  def ligada?(forma)
    config[forma.to_s].present?
  end

  private

  def liberado?(username)
    return true if config['todos'].present?
    return false if username.blank?

    allowlist.include?(username.to_s.downcase.delete_prefix('@'))
  end

  def allowlist
    @allowlist ||= Array(config['allowlist']).map { |nome| nome.to_s.downcase.delete_prefix('@') }.compact_blank
  end

  def config
    @config ||= (account.settings || {})['social_reply'].presence || {}
  end
end
