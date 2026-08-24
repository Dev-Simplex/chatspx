# Grava um comentário público que chegou pelo webhook (`field: comments`).
#
# ORDEM DE PROPÓSITO: o comentário é gravado ANTES de qualquer conversa com a Graph. A publicação
# nasce com o que o próprio payload dá (id e tipo) e só depois tenta buscar legenda e permalink.
# Se a Graph estiver fora, perde-se a legenda — não o comentário. Este serviço existe justamente
# porque comentário estava sendo perdido; trocar um jeito de perder por outro não seria conserto.
module Spx
  module Social
    class InstagramComentarioService
      pattr_initialize [:value!, :channel!, :ocorrido_em]

      def perform
        return if external_id.blank?
        return if inbox.blank?

        comentario = gravar
        sincronizar_publicacao(comentario)
        comentario
      end

      private

      def gravar
        # `create_or_find_by` e não `find_or_create_by`: a Meta reentrega o mesmo comentário
        # (medido: 51 entregas para 39 comentários em 7 dias), e duas entregas simultâneas
        # correriam no `find`. Aqui o índice único decide, e o perdedor lê a linha existente.
        Spx::Social::Comentario.create_or_find_by!(
          account_id: inbox.account_id,
          external_id: external_id
        ) do |c|
          c.inbox_id = inbox.id
          c.publicacao_external_id = publicacao_external_id
          c.autor_external_id = value.dig(:from, :id)
          c.autor_username = value.dig(:from, :username)
          c.texto = value[:text]
          c.proprio = proprio?
          c.comentado_em = ocorrido_em
          c.payload = value.as_json
        end
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
        ) do |p|
          p.inbox_id = inbox.id
          p.tipo = value.dig(:media, :media_product_type)
        end

        comentario.update!(publicacao_id: publicacao.id) if comentario.publicacao_id != publicacao.id
        Spx::Social::InstagramPublicacaoSync.new(publicacao: publicacao, channel: channel).perform
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
  end
end
