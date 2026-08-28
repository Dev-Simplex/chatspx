# Envia o pin de localizacao de um IMOVEL (lat/lng do Vista) pelo pipeline nativo do SPX.
# Gemea da EnviarLocalizacaoTool, mas busca as coordenadas do imovel no Vista por codigo.
class Captain::Tools::EnviarLocalizacaoImovelTool < Captain::Tools::BasePublicTool
  description 'Envia ao cliente a localização (pin no mapa) de um imóvel pelo WhatsApp. ' \
              'Chame SOMENTE quando o cliente PEDIR explicitamente onde fica o imóvel / a localização dele — ' \
              'NUNCA por conta própria nem antecipe o ponto sem ele pedir. Informe o código (vem do resultado da busca).'

  param :codigo, type: 'string',
                 desc: 'Código do imóvel que o cliente quer, exatamente como veio no resultado da busca DAQUELE imóvel. ' \
                       'Nunca reutilize o código de outro imóvel, nunca invente.', required: true

  # Quanto o centroide do bairro pode distar do imóvel real antes de ser considerado
  # resultado de outra cidade (ver pin_do_bairro).
  TOLERANCIA_BAIRRO_KM = 3.0

  # [lat, lng, título, escopo] quando não há pin a enviar.
  SEM_PIN = [nil, nil, nil, nil].freeze

  def perform(tool_context, codigo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra enviar a localização.' unless conversation

    lat, lng, nome, escopo = fetch_coordinates(codigo)
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
    log_tool_usage('enviar_localizacao_imovel', conversation_id: conversation.id, codigo: codigo, escopo: escopo)
    confirmacao(codigo, nome, escopo)
  rescue StandardError => e
    Rails.logger.warn("[EnviarLocalizacaoImovelTool] #{e.message}")
    'Não consegui enviar a localização agora.'
  end

  # O retorno diz à IA O QUE foi enviado. Sem isso ela anuncia "mandei a localização do imóvel"
  # depois de mandar o pin do bairro, e a promessa não bate com o que o cliente recebeu.
  def confirmacao(codigo, nome, escopo)
    if escopo == :bairro
      "Enviei ao cliente o pin do BAIRRO #{nome} — não o ponto exato do imóvel #{codigo}, porque em " \
        'imóvel à venda a Tozi divulga só a região. Diga com naturalidade que mandou a localização da ' \
        'região e que o endereço exato o corretor mostra na visita. NUNCA escreva a rua ou o número.'
    else
      "Pin de localização do imóvel #{codigo} enviado ao cliente. Confirme com naturalidade e siga a conversa."
    end
  end

  private

  def fetch_coordinates(codigo)
    # Credenciais Vista por CONTA via concern (AccountIntegration -> custom_attributes -> ENV).
    base = vista_base_url
    pesquisa = { fields: %w[Codigo Categoria Status Bairro BairroComercial Latitude Longitude] }
    resp = HTTParty.get(
      "#{base}/imoveis/detalhes",
      query: { key: vista_api_key, imovel: codigo, pesquisa: pesquisa.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: 15
    )
    return SEM_PIN unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return SEM_PIN unless data.is_a?(Hash)

    montar_pin(data, codigo)
  end

  def montar_pin(data, codigo)
    lat = data['Latitude'].to_f
    lng = data['Longitude'].to_f
    return SEM_PIN if lat.zero? || lng.zero?

    bairro = data['BairroComercial'].presence || data['Bairro']
    return pin_do_bairro(bairro, lat, lng) if venda?(data)

    # NÃO incluir nome de negócio ("Tozi Imóveis") no título: o WhatsApp/Google Maps
    # snapa o pin pro POI da empresa em vez das coordenadas do imóvel (abria no escritório).
    [lat, lng, "Imóvel cód #{codigo}#{bairro ? " - #{bairro}" : ''}", :imovel]
  end

  def venda?(data)
    data['Status'].to_s.match?(/vend/i)
  end

  # Em VENDA o pin é do BAIRRO, não da porta. Régua do cliente: locação pode endereço
  # completo, venda só o bairro — coordenada exata de imóvel à venda é o que um concorrente
  # usa pra ir captar o imóvel direto com o proprietário. Medido em 28/08: 7 dos 33 pins
  # enviados em 30 dias eram de imóveis à venda.
  #
  # A coordenada vem do Google (o centroide do bairro), NUNCA do nosso acervo: 116 dos 241
  # bairros de venda têm um único imóvel, e nesses o "centro do acervo" seria a porta dele —
  # reintroduziria o vazamento com outro nome. O acervo entra só como VERIFICADOR: se o pin
  # do Google cair longe do imóvel real, ele é de outra cidade (o Google devolve homônimo em
  # vez de dizer que não achou — 67 dos 259 bairros caíram assim, o pior a 518 km) e aí não
  # sai pin nenhum.
  def pin_do_bairro(bairro, imovel_lat, imovel_lng)
    return SEM_PIN if bairro.blank?

    ponto = geocode_bairro(bairro)
    return SEM_PIN if ponto.nil?
    return SEM_PIN if haversine_km(ponto[:lat], ponto[:lng], imovel_lat, imovel_lng) > TOLERANCIA_BAIRRO_KM

    [ponto[:lat], ponto[:lng], bairro.to_s.strip, :bairro]
  end

  def geocode_bairro(bairro)
    key = google_maps_key
    return nil if key.blank?

    Rails.cache.fetch("captain:geo:#{tool_account&.id}:#{bairro.to_s.downcase.strip}", expires_in: 30.days) do
      consultar_google(bairro, key)
    end
  rescue StandardError => e
    Rails.logger.warn("[EnviarLocalizacaoImovelTool] geocode_bairro(#{bairro}): #{e.message}")
    nil
  end

  def consultar_google(bairro, key)
    resp = HTTParty.get('https://maps.googleapis.com/maps/api/geocode/json',
                        query: { address: "#{bairro} #{geo_city}", key: key, region: 'br', language: 'pt-BR' },
                        timeout: 10)
    return nil unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return nil unless data.is_a?(Hash) && data['status'] == 'OK'

    loc = data.dig('results', 0, 'geometry', 'location')
    loc && { lat: loc['lat'].to_f, lng: loc['lng'].to_f }
  end

  def haversine_km(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = (Math.sin(dlat / 2)**2) + (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlng / 2)**2))
    2 * 6371 * Math.asin(Math.sqrt(a))
  end
end
