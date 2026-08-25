json.array! @comentarios do |comentario|
  json.id comentario.id
  json.texto comentario.texto
  json.autor_username comentario.autor_username
  json.comentado_em comentario.comentado_em
  json.proprio comentario.proprio
  # Derivado do @ no começo da resposta da conta, não de `parent_id` — a Meta não manda um.
  # Ver Spx::Social::Respondidos. A tela precisa dizer que isto é inferência.
  json.respondido @respondidos.respondido?(comentario)

  if comentario.publicacao
    json.publicacao do
      json.id comentario.publicacao.id
      json.tipo comentario.publicacao.tipo
      json.legenda comentario.publicacao.legenda
      json.permalink comentario.publicacao.permalink
      json.thumbnail_url comentario.publicacao.thumbnail_url
    end
  end
end
