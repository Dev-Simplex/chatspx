# Grava um comentário público que chegou pelo webhook (`field: comments`).
#
# ORDEM DE PROPÓSITO: o comentário é gravado ANTES de qualquer conversa com a Graph. A publicação
# nasce com o que o próprio payload dá (id e tipo) e só depois tenta buscar legenda e permalink.
# Se a Graph estiver fora, perde-se a legenda — não o comentário. Este serviço existe justamente
# porque comentário estava sendo perdido; trocar um jeito de perder por outro não seria conserto.
class Spx::Social::InstagramComentarioService
  pattr_initialize [:value!, :channel!, :ocorrido_em]

  def perform
    return if external_id.blank?
    return if inbox.blank?

    comentario = gravar
    novo = comentario.previously_new_record?
    sincronizar_publicacao(comentario)
    acordar_ia(comentario) if novo
    comentario
  end

  private

  def gravar
    # `create_or_find_by!` e não `find_or_create_by`: a Meta reentrega o mesmo comentário
    # (medido: 51 entregas para 39 comentários em 7 dias), e duas entregas simultâneas
    # correriam no `find`. Aqui o índice único decide, e o perdedor lê a linha existente.
    Spx::Social::Comentario.create_or_find_by!(
      account_id: inbox.account_id,
      external_id: external_id
    ) do |comentario|
      comentario.assign_attributes(atributos)
    end
  end

  def atributos
    {
      inbox_id: inbox.id,
      publicacao_external_id: publicacao_external_id,
      autor_external_id: value.dig(:from, :id),
      autor_username: value.dig(:from, :username),
      texto: value[:text],
      proprio: proprio?,
      comentado_em: ocorrido_em,
      payload: value.as_json
    }
  end

  # A conta comentando na própria publicação — é a resposta pública do time. Guardamos (a
  # tela precisa mostrar o que já foi respondido), mas nada além disso deve reagir a ela:
  # sem esta marca, um agente responderia à própria resposta, indefinidamente.
  def proprio?
    autor = value.dig(:from, :id).to_s

    autor.present? && autor == channel.instagram_id.to_s
  end

  def sincronizar_publicacao(comentario)
    return if publicacao_external_id.blank?

    publicacao = Spx::Social::Publicacao.create_or_find_by!(
      account_id: inbox.account_id,
      external_id: publicacao_external_id
    ) do |nova|
      nova.inbox_id = inbox.id
      nova.tipo = value.dig(:media, :media_product_type)
    end

    comentario.update!(publicacao_id: publicacao.id) if comentario.publicacao_id != publicacao.id
    Spx::Social::InstagramPublicacaoSync.new(publicacao: publicacao, channel: channel).perform
  end

  # Só comentário NOVO acorda a IA. A Meta reentrega (51 entregas para 39 comentários em 7 dias),
  # e sem esta guarda cada reentrega geraria uma resposta — na privada, que é uma por comentário,
  # a segunda tentativa queimaria a única chance.
  #
  # A conta da própria casa nunca acorda ninguém: seria a IA respondendo a si mesma.
  def acordar_ia(comentario)
    return if comentario.proprio?

    Spx::Social::ResponderComentarioComIaJob.perform_later(comentario.id)
  end

  def external_id
    @external_id ||= value[:id].to_s.presence
  end

  def publicacao_external_id
    @publicacao_external_id ||= value.dig(:media, :id).to_s.presence
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
