class Captain::Tools::EnviarFotosImovelTool < Captain::Tools::BasePublicTool
  description 'Envia ao cliente as fotos reais de um imóvel pelo WhatsApp, em lotes de 3. ' \
              'Chame quando o cliente pedir fotos de um imóvel, informando o código (vem do resultado da busca). ' \
              'Se o cliente pedir mais fotos do mesmo imóvel, chame de novo com o mesmo código que envia as próximas 3.'

  param :codigo, type: 'string', desc: 'Código do imóvel (ex: 6573), tirado do resultado da busca.', required: true

  BATCH = 3
  SEND_INTERVAL = 2 # segundos entre cada foto, pra o WhatsApp entregar uma por uma

  def perform(tool_context, codigo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra enviar as fotos.' unless conversation

    fotos = fetch_fotos(codigo)
    return 'Não encontrei fotos desse imóvel.' if fotos.blank?

    key = "fotos_offset_#{codigo}"
    sent = conversation.custom_attributes[key].to_i
    batch = fotos[sent, BATCH] || []
    if batch.empty?
      # Cliente pediu fotos de novo e ja enviamos todas: recomeca do inicio (reenvio —
      # cobre tambem o caso de as anteriores nao terem chegado).
      sent = 0
      batch = fotos[0, BATCH] || []
    end
    return 'Não encontrei fotos desse imóvel.' if batch.empty?

    # Envia uma por uma com intervalo: em rajada o bridge do WhatsApp entrega só a 1ª.
    batch.each_with_index do |url, i|
      send_photo(conversation, url)
      sleep(SEND_INTERVAL) if i < batch.size - 1
    end
    new_sent = sent + batch.size
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(key => new_sent))

    restantes = fotos.size - new_sent
    if restantes.positive?
      "Enviei #{batch.size} fotos do imóvel #{codigo}. Ainda tenho mais #{restantes}; ofereça enviar se o cliente quiser."
    else
      "Enviei as últimas #{batch.size} fotos do imóvel #{codigo}. Não há mais fotos."
    end
  rescue StandardError => e
    Rails.logger.warn("[EnviarFotosImovelTool] #{e.message}")
    'Não consegui enviar as fotos agora.'
  end

  private

  def fetch_fotos(codigo)
    base = ENV.fetch('TOZI_VISTA_BASE_URL', 'https://toz19328-rest.vistahost.com.br')
    pesquisa = { fields: ['Codigo', { 'Foto' => %w[Foto Destaque] }] }
    resp = HTTParty.get(
      "#{base}/imoveis/detalhes",
      query: { key: ENV['TOZI_VISTA_API_KEY'].to_s, imovel: codigo, pesquisa: pesquisa.to_json },
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

  def send_photo(conversation, url)
    io = Down.download(url, max_size: 15 * 1024 * 1024)
    # Anexo construido ANTES do save: o envio dispara no after_create_commit da mensagem,
    # entao criar o attachment depois (create! + create!) e corrida — o WhatsApp Cloud
    # recebia payload de texto com body vazio e recusava (text.body expected string).
    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant
    )
    msg.attachments.build(
      account_id: conversation.account_id,
      file_type: :image,
      file: { io: io, filename: File.basename(URI.parse(url).path), content_type: 'image/jpeg' }
    )
    msg.save!
  end
end
