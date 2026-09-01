json.formas do
  # Quais formas estão ligadas NESTA conta. A tela só oferece o que a conta habilitou — botão que
  # existe e sempre recusa é pior que botão ausente.
  Spx::Social::PoliticaDeResposta::FORMAS.each do |forma|
    json.set! forma, @politica.ligada?(forma)
  end
end

json.comentarios @comentarios do |comentario|
  json.id comentario.id
  json.texto comentario.texto
  json.autor_username comentario.autor_username
  json.comentado_em comentario.comentado_em
  json.proprio comentario.proprio
  # Derivado do @ no começo da resposta da conta, não de `parent_id` — a Meta não manda um.
  # Ver Spx::Social::Respondidos. A tela precisa dizer que isto é inferência.
  json.respondido @respondidos.respondido?(comentario)

  # O que já saiu daqui, por forma, e por que cada forma pode ou não ser usada agora. A tela
  # DIZ o motivo da recusa: "não aconteceu nada" é a pior resposta possível para quem opera.
  json.respostas comentario.respostas_registradas
  json.recusas do
    Spx::Social::PoliticaDeResposta::FORMAS.each do |forma|
      json.set! forma, @politica.motivo_da_recusa(comentario, forma)
    end
  end

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
