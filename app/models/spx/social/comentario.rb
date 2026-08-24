# Comentário público numa publicação. Ver a migration pro porquê de não ser uma `Conversation`.
module Spx
  module Social
    class Comentario < ApplicationRecord
      self.table_name = 'social_comentarios'

      belongs_to :account
      belongs_to :inbox
      belongs_to :publicacao, class_name: 'Spx::Social::Publicacao', optional: true,
                              inverse_of: :comentarios

      validates :external_id, presence: true, uniqueness: { scope: :account_id }

      # O que o cliente escreveu. Exclui o que a própria conta comentou — que é resposta do
      # time, e é o que sobra quando alguém pergunta "o que ainda não foi respondido".
      scope :de_terceiros, -> { where(proprio: false) }
      scope :da_conta, -> { where(proprio: true) }
    end
  end
end
