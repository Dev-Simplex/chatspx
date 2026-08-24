# Superfície de rede social — comentário público e a publicação a que ele pertence.
#
# POR QUE UMA TABELA, E NÃO UMA CONVERSA (decisão do Paulo, 18/08): comentário não é atendimento
# 1-pra-1. Ele é público, pertence a uma publicação, e o que importa dele é o conjunto — "o que
# estão perguntando embaixo deste reel" — não o fio individual. Modelar como `Conversation`
# empurraria comentário pra fila do time e misturaria com DM, que é outro trabalho.
#
# POR QUE ISTO EXISTE AGORA: medido na .232 em 24/08, os comentários da BigStore JÁ CHEGAM no
# webhook (`field: comments`, assinatura ligada em 18/08) e são descartados em silêncio pelo
# `Webhooks::InstagramEventsJob#test_event?`, que trata todo `changes` como evento de teste.
# Eram 39 comentários distintos em 7 dias indo pro vazio.
#
# DUAS COISAS QUE A MEDIÇÃO IMPÔS AO SCHEMA:
#   1. `external_id` é ÚNICO por conta. A Meta reentrega: 51 entregas para 39 comentários em
#      7 dias. Sem o índice, cada redelivery viraria uma linha nova.
#   2. `proprio` existe como coluna. 22 das 51 entregas eram da PRÓPRIA @bigstoreutilidades —
#      o webhook devolve o que a conta comenta, inclusive as respostas do time. Sem essa marca,
#      um agente responderia a si mesmo em loop. Guardamos (é o histórico de resposta pública
#      do time, e a tela precisa dele), mas nunca acordamos ninguém com isso.
class CreateSocialComentarios < ActiveRecord::Migration[7.1]
  def change
    criar_publicacoes
    criar_comentarios
  end

  private

  def criar_publicacoes
    create_table :social_publicacoes do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id,   null: false
      # Id da mídia na Meta. Vem no próprio payload do comentário (`value.media.id`), então a
      # publicação nasce da primeira pessoa que comenta nela — não de uma varredura periódica.
      t.string :external_id, null: false
      # REELS / FEED / STORY — vem de graça no payload (`media_product_type`).
      t.string :tipo
      # Sem legenda a IA responde "quanto custa?" sem saber do quê, e a tela mostra um comentário
      # órfão de contexto. É o dado que faz tela e cérebro serem a mesma obra.
      t.text   :legenda
      t.string :permalink
      t.string :thumbnail_url
      t.datetime :publicada_em
      # like_count / comments_count. Fica em jsonb porque a lista de métricas muda com o escopo
      # de insights (alcance, salvamentos, compartilhamentos) e não vale uma coluna por métrica.
      t.jsonb  :metricas, null: false, default: {}
      # Quando falamos com a Graph pela última vez. Nulo = nasceu só com o que o webhook deu.
      t.datetime :sincronizada_em
      t.timestamps
    end
    add_index :social_publicacoes, %i[account_id external_id], unique: true
    add_index :social_publicacoes, :inbox_id
  end

  def criar_comentarios
    create_table :social_comentarios do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id,   null: false
      # Nulo enquanto a publicação não foi resolvida. O comentário NÃO espera pela Graph pra ser
      # gravado — perder o comentário porque a API demorou seria repetir o defeito que isto
      # conserta. O `publicacao_external_id` segura o vínculo até a resolução acontecer.
      t.bigint :publicacao_id
      t.string :publicacao_external_id
      t.string :external_id, null: false
      t.string :autor_external_id
      t.string :autor_username
      t.text   :texto
      # Comentário feito pela própria conta — resposta do time, não pergunta de cliente.
      t.boolean :proprio, null: false, default: false
      t.datetime :comentado_em
      # Payload cru. A Meta OMITE campo em silêncio quando falta permissão (devolve 200 sem o
      # campo, não erro) — guardar o que chegou é a única forma de diagnosticar depois por que
      # um comentário veio sem autor.
      t.jsonb  :payload, null: false, default: {}
      t.timestamps
    end
    add_index :social_comentarios, %i[account_id external_id], unique: true
    add_index :social_comentarios, :publicacao_id
    add_index :social_comentarios, %i[inbox_id created_at]
  end
end
