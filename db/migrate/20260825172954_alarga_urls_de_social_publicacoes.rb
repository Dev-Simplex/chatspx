# URL de mídia do Instagram não cabe em 255 caracteres.
#
# Pego em execução ao vivo, não em teste: o CDN da Meta devolve `thumbnail_url` com assinatura e
# parâmetros de expiração, bem acima do limite de `string`. O `update!` do sync estourava
# `RecordInvalid` — e como ele roda no meio da captura, a exceção subia e **matava o gatilho da
# IA**. O comentário sobrevivia (é gravado antes), mas ninguém era acordado para responder.
#
# `string` para URL é limite arbitrário: nenhum sistema promete que uma URL cabe em 255. Vira
# `text`, que é o que o Postgres já usa por baixo dos dois casos.
class AlargaUrlsDeSocialPublicacoes < ActiveRecord::Migration[7.1]
  def up
    change_column :social_publicacoes, :thumbnail_url, :text
    change_column :social_publicacoes, :permalink, :text
  end

  def down
    change_column :social_publicacoes, :thumbnail_url, :string
    change_column :social_publicacoes, :permalink, :string
  end
end
