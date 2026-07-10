# Envia o pin de localizacao de um IMOVEL (lat/lng do Vista) pelo pipeline nativo do SPX.
# Gemea da EnviarLocalizacaoTool, mas busca as coordenadas do imovel no Vista por codigo.
class Captain::Tools::EnviarLocalizacaoImovelTool < Captain::Tools::BasePublicTool
  description 'Envia ao cliente a localização (pin no mapa) de um imóvel pelo WhatsApp. ' \
              'Chame SOMENTE quando o cliente PEDIR explicitamente onde fica o imóvel / a localização dele — ' \
              'NUNCA por conta própria nem antecipe o ponto sem ele pedir. Informe o código (vem do resultado da busca).'

  param :codigo, type: 'string',
        desc: 'Código do imóvel que o cliente quer, exatamente como veio no resultado da busca DAQUELE imóvel. ' \
              'Nunca reutilize o código de outro imóvel, nunca invente.', required: true

  def perform(tool_context, codigo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra enviar a localização.' unless conversation

    lat, lng, nome = fetch_coordinates(codigo)
    if lat.nil?
      return "Esse imóvel (cód #{codigo}) não tem a localização cadastrada no sistema. " \
             'Diga ao cliente com naturalidade que vai confirmar o ponto certo com o corretor.'
    end

    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant
    )
    msg.attachments.build(
      account_id: conversation.account_id,
      file_type: :location,
      coordinates_lat: lat,
      coordinates_long: lng,
      fallback_title: nome
    )
    msg.save!
    log_tool_usage('enviar_localizacao_imovel', conversation_id: conversation.id, codigo: codigo)
    "Pin de localização do imóvel #{codigo} enviado ao cliente. Confirme com naturalidade e siga a conversa."
  rescue StandardError => e
    Rails.logger.warn("[EnviarLocalizacaoImovelTool] #{e.message}")
    'Não consegui enviar a localização agora.'
  end

  private

  def fetch_coordinates(codigo)
    # Credenciais Vista por CONTA via concern (AccountIntegration -> custom_attributes -> ENV).
    base = vista_base_url
    pesquisa = { fields: %w[Codigo Categoria Bairro BairroComercial Latitude Longitude] }
    resp = HTTParty.get(
      "#{base}/imoveis/detalhes",
      query: { key: vista_api_key, imovel: codigo, pesquisa: pesquisa.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: 15
    )
    return [nil, nil, nil] unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return [nil, nil, nil] unless data.is_a?(Hash)

    lat = data['Latitude'].to_f
    lng = data['Longitude'].to_f
    return [nil, nil, nil] if lat.zero? || lng.zero?

    bairro = data['BairroComercial'].presence || data['Bairro']
    nome = "Imóvel cód #{codigo}#{bairro ? " - #{bairro}" : ''}"
    [lat, lng, nome]
  end
end
