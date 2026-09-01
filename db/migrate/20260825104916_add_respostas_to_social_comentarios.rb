# Registro das tentativas de resposta a um comentário.
#
# POR QUE UMA COLUNA E NÃO UM BOOLEANO: a resposta privada (DM em resposta a comentário) é **uma
# por comentário**, com janela, e **sem segunda chance** — errar e tentar de novo não é opção.
# Então o que precisa ficar gravado não é "respondi", é *o que aconteceu na tentativa*: quando,
# qual id a Meta devolveu, e o erro quando falhou. Sem isso, um retry cego queima a única chance.
#
# jsonb com uma chave por FORMA (`publica` / `privada`) porque as duas são independentes e têm
# chave de configuração separada: o mesmo comentário pode receber as duas, ou só uma.
#
#   {"privada": {"em": "...", "external_id": "aWdt...", "erro": null},
#    "publica": {"em": "...", "external_id": "179...",  "erro": null}}
#
# Tentativa que falhou fica gravada com o erro e SEM `external_id` — é o que distingue
# "ninguém tentou" de "tentou e a Meta recusou", que são situações opostas para quem opera.
class AddRespostasToSocialComentarios < ActiveRecord::Migration[7.1]
  def change
    # `if_not_exists` porque a migration é aplicada com alvo, VM a VM, e outra frente pode ter
    # tocado a mesma tabela num banco de teste — transforma um aborto de lote num no-op.
    add_column :social_comentarios, :respostas, :jsonb, null: false, default: {}, if_not_exists: true
  end
end
