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

  # Tentativas de resposta, uma chave por forma. Ver a migration para o porquê de registrar a
  # tentativa e não só um booleano.
  #
  # Tolerante à coluna AUSENTE, como `Spx::Distribuicao::Produto#apresentacao_config`: a migration
  # é aplicada com alvo, VM a VM, então este código roda em box onde ela ainda não existe. Sem a
  # coluna, nada foi respondido e nada é gravado — o comportamento é o de antes.
  def respostas_registradas
    return {} unless has_attribute?(:respostas)

    respostas.presence || {}
  end

  # Só conta como respondido o que a Meta ACEITOU. Tentativa que falhou fica gravada com o erro
  # e sem `external_id`, e continua aparecendo como pendente — senão uma falha silenciosa
  # esconderia um cliente sem resposta, que é o oposto do que esta tela existe para fazer.
  def respondido_em?(forma)
    respostas_registradas.dig(forma.to_s, 'external_id').present?
  end

  def registrar_resposta!(forma, external_id: nil, erro: nil)
    return unless has_attribute?(:respostas)

    update!(respostas: respostas_registradas.merge(
      forma.to_s => { 'em' => Time.current.iso8601, 'external_id' => external_id, 'erro' => erro }
    ))
  end
end
