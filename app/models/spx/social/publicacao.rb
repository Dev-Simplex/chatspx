# Publicação de rede social (hoje só Instagram), guardada porque o comentário sozinho não se
# explica: sem legenda e miniatura, "quanto custa?" não tem sujeito — nem pra pessoa que olha a
# tela, nem pro agente que fosse responder.
#
# Nasce do PRIMEIRO comentário que chega nela (o payload traz `value.media.id` e o
# `media_product_type`), não de varredura periódica. Publicação sem comentário nenhum não
# interessa a esta superfície.
module Spx
  module Social
    class Publicacao < ApplicationRecord
      self.table_name = 'social_publicacoes'

      belongs_to :account
      belongs_to :inbox
      has_many :comentarios, class_name: 'Spx::Social::Comentario', dependent: :nullify,
                             foreign_key: :publicacao_id, inverse_of: :publicacao

      validates :external_id, presence: true, uniqueness: { scope: :account_id }

      # Só o webhook alimentou esta linha — ninguém falou com a Graph ainda, então legenda,
      # permalink e miniatura estão vazios. É estado normal, não erro: o comentário é gravado
      # sem esperar a API.
      def sincronizada?
        sincronizada_em.present?
      end
    end
  end
end
