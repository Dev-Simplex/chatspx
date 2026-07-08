class Captain::Tools::EnviarFotosImovelTool < Captain::Tools::BasePublicTool
  description 'Envia ao cliente as fotos reais de um imóvel pelo WhatsApp, em lotes de 3. ' \
              'Chame quando o cliente pedir fotos de um imóvel, informando o código (vem do resultado da busca). ' \
              'Se o cliente pedir mais fotos do mesmo imóvel, chame de novo com o mesmo código que envia as próximas 3.'

  param :codigo, type: 'string',
                 desc: 'Código do imóvel que o cliente quer, exatamente como veio no resultado da busca DAQUELE imóvel. ' \
                       'Nunca reutilize o código de outro imóvel, nunca invente.', required: true

  BATCH = 3
  SEND_INTERVAL = 2 # segundos entre cada foto, pra o WhatsApp entregar uma por uma
  COOLDOWN = 90 # segundos entre lotes de foto na MESMA conversa — freia a rajada multi-imóvel
  MAX_POR_IMOVEL = 6 # teto de fotos por imóvel (2 lotes) — evita dilúvio

  def perform(tool_context, codigo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra enviar as fotos.' unless conversation

    # Freio anti-rajada: não deixa a IA despejar fotos de vários imóveis no mesmo turno
    # (era o "todas juntas"). O 1º lote da conversa sempre passa (ultimo=0).
    ultimo = conversation.custom_attributes['fotos_ultimo_envio_at'].to_i
    if ultimo.positive? && (Time.current.to_i - ultimo) < COOLDOWN
      return 'Você acabou de enviar fotos há pouco. NÃO envie mais fotos agora — avance a conversa e ' \
             'espere o cliente reagir. Só envie de novo se ele pedir explicitamente.'
    end

    # Trava anti-alucinação: só envia foto de código que apareceu numa busca DESTA
    # conversa (buscar_imovel registra em codigos_buscados). Bloqueia a IA de mandar
    # foto de um código que ela supôs/lembrou (ex.: mandar prédio comercial por casa).
    cod = codigo.to_s.gsub(/\D/, '')
    vistos = Array(conversation.custom_attributes['codigos_buscados']).map(&:to_s)
    if vistos.any? && !vistos.include?(cod)
      return "O código #{cod} não apareceu na busca desta conversa. Use buscar_imovel primeiro e envie fotos SÓ de um código que a busca retornou — nunca de um código que você supôs ou lembrou de outro imóvel."
    end

    fotos = fetch_fotos(codigo)
    return 'Não encontrei fotos desse imóvel.' if fotos.blank?

    key = "fotos_offset_#{codigo}"
    sent = conversation.custom_attributes[key].to_i
    limite = [fotos.size, MAX_POR_IMOVEL].min
    if sent >= limite
      # Já enviou o teto (ou todas): NÃO reenvia do zero (evita foto repetida) — avança.
      return "Já enviei as fotos principais do imóvel #{codigo}. NÃO reenvie — avance a conversa (interesse, visita)."
    end

    batch = fotos[sent, BATCH] || []
    return 'Não encontrei fotos desse imóvel.' if batch.empty?

    # Envia uma por uma com intervalo: em rajada o bridge do WhatsApp entrega só a 1ª.
    batch.each_with_index do |url, i|
      send_photo(conversation, url, codigo)
      sleep(SEND_INTERVAL) if i < batch.size - 1
    end
    new_sent = sent + batch.size
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(
      key => new_sent, 'fotos_ultimo_envio_at' => Time.current.to_i
    ))

    if limite - new_sent > 0
      # Nao oferecer mais fotos por conta propria (prende o lead num loop de midia):
      # avancar a conversa pro proximo passo; se o cliente pedir mais, chamar de novo.
      "Enviei #{batch.size} fotos do imóvel #{codigo}. NÃO ofereça mais fotos por conta própria — " \
        'avance a conversa pro próximo passo (interesse, visita). Se o cliente pedir mais fotos, chame esta ferramenta de novo.'
    else
      "Enviei as fotos principais do imóvel #{codigo}. Avance a conversa."
    end
  rescue StandardError => e
    Rails.logger.warn("[EnviarFotosImovelTool] #{e.message}")
    'Não consegui enviar as fotos agora.'
  end

  private

  def fetch_fotos(codigo)
    # Credenciais Vista por CONTA via concern (AccountIntegration -> custom_attributes -> ENV).
    base = vista_base_url
    pesquisa = { fields: ['Codigo', { 'Foto' => %w[Foto Destaque] }] }
    resp = HTTParty.get(
      "#{base}/imoveis/detalhes",
      query: { key: vista_api_key, imovel: codigo, pesquisa: pesquisa.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: 15
    )
    return [] unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    fotos = data.is_a?(Hash) ? data['Foto'] : nil
    return [] unless fotos.is_a?(Hash)

    # Destaque primeiro, depois o resto, na ordem das chaves
    fotos.values
         .sort_by { |f| [f['Destaque'] == 'Sim' ? 0 : 1] }
         .filter_map { |f| f['Foto'] }
  end

  def send_photo(conversation, url, codigo)
    io = Down.download(url, max_size: 15 * 1024 * 1024)
    # Anexo construido ANTES do save: o envio dispara no after_create_commit da mensagem,
    # entao criar o attachment depois (create! + create!) e corrida — o WhatsApp Cloud
    # recebia payload de texto com body vazio e recusava (text.body expected string).
    # property_code carimba a qual imovel a foto pertence: sem isso a foto e um outgoing
    # de conteudo vazio, indistinguivel no historico e no reply-context (o "esse e qual?").
    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      additional_attributes: { 'property_code' => codigo }
    )
    msg.attachments.build(
      account_id: conversation.account_id,
      file_type: :image,
      file: { io: io, filename: File.basename(URI.parse(url).path), content_type: 'image/jpeg' }
    )
    msg.save!
  end
end
