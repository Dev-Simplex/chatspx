class Captain::Tools::EnviarFotosImovelTool < Captain::Tools::BasePublicTool
  description 'Envia ao cliente as fotos reais de um imóvel pelo WhatsApp, em lotes de 3. ' \
              'Chame quando o cliente pedir fotos de um imóvel, informando o código (vem do resultado da busca). ' \
              'Se o cliente pedir mais fotos do mesmo imóvel, chame de novo com o mesmo código que envia as próximas 3.'

  param :codigo, type: 'string', desc: 'Código do imóvel (ex: 6573), tirado do resultado da busca.', required: true

  BATCH = 3

  def perform(tool_context, codigo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra enviar as fotos.' unless conversation

    fotos = fetch_fotos(codigo)
    return 'Não encontrei fotos desse imóvel.' if fotos.blank?

    key = "fotos_offset_#{codigo}"
    sent = conversation.custom_attributes[key].to_i
    batch = fotos[sent, BATCH] || []
    return 'Já enviei todas as fotos que tenho desse imóvel.' if batch.empty?

    batch.each { |url| send_photo(conversation, url) }
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
    msg = conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant
    )
    msg.attachments.create!(
      account_id: conversation.account_id,
      file_type: :image,
      file: { io: io, filename: File.basename(URI.parse(url).path), content_type: 'image/jpeg' }
    )
  end
end
