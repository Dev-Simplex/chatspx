# Comentário público numa publicação. Ver a migration pro porquê de não ser uma `Conversation`.
class Spx::Social::Comentario < ApplicationRecord
  self.table_name = 'social_comentarios'

  belongs_to :account
  belongs_to :inbox
  belongs_to :publicacao, class_name: 'Spx::Social::Publicacao', optional: true,
                          inverse_of: :comentarios

  # Quem garante unicidade é o ÍNDICE do banco, não uma validação de model. Validação de
  # unicidade tem corrida entre o SELECT e o INSERT — e aqui a corrida é o caso normal, não a
  # borda: a Meta reentrega o mesmo comentário, e duas entregas podem cair em dois workers.
  # `create_or_find_by!` depende de o banco levantar `RecordNotUnique`; com a validação no
  # model, ela dispararia antes e o serviço estouraria em vez de reaproveitar a linha.
  validates :external_id, presence: true

  # O que o cliente escreveu. Exclui o que a própria conta comentou — que é resposta do
  # time, e é o que sobra quando alguém pergunta "o que ainda não foi respondido".
  scope :de_terceiros, -> { where(proprio: false) }
  scope :da_conta, -> { where(proprio: true) }
end
