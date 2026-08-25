json.array! @publicacoes do |publicacao|
  json.id publicacao.id
  json.external_id publicacao.external_id
  json.tipo publicacao.tipo
  json.legenda publicacao.legenda
  json.permalink publicacao.permalink
  json.thumbnail_url publicacao.thumbnail_url
  json.publicada_em publicacao.publicada_em
  json.sincronizada publicacao.sincronizada?
  json.metricas publicacao.metricas

  # Capturados por nós, separando o que é pergunta de cliente do que é resposta do time.
  json.comentarios_de_terceiros(@capturados[[publicacao.id, false]] || 0)
  json.respostas_da_conta(@capturados[[publicacao.id, true]] || 0)
end
