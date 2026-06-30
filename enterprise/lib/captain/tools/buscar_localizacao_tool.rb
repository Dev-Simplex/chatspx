class Captain::Tools::BuscarLocalizacaoTool < Captain::Tools::BasePublicTool
  description 'Geocodifica um endereço, bairro ou ponto de referência em Sinop-MT e retorna ' \
              'as coordenadas (lat/lng) e o endereço formatado. Use quando precisar das ' \
              'coordenadas de um local pra passar pro buscar_imovel (filtro por proximidade).'

  param :local, type: 'string',
                desc: 'Endereço, bairro ou ponto de referência a localizar ' \
                      '(ex: "Jardim Botânico", "Av. das Figueiras 1646").',
                required: true

  def perform(_tool_context, local:)
    # Chave Google por CONTA via o concern IntegrationCredentials
    # (AccountIntegration -> custom_attributes -> ENV). Substitui a antiga custom
    # tool custom_buscar_localizacao_geocoding (chave saiu da URL pro account_integrations).
    key = google_maps_key
    return 'Busca de localização indisponível no momento.' if key.blank?

    result = geocode("#{local} Sinop MT", key)
    return "Não achei a localização de \"#{local}\" em Sinop." if result.blank?

    loc = result.dig('geometry', 'location') || {}
    "Localização de \"#{local}\": #{result['formatted_address']} " \
      "[lat=#{loc['lat']}, lng=#{loc['lng']}]"
  rescue StandardError => e
    Rails.logger.warn("[BuscarLocalizacaoTool] #{e.message}")
    'Não consegui buscar a localização agora.'
  end

  private

  def geocode(address, key)
    resp = HTTParty.get(
      'https://maps.googleapis.com/maps/api/geocode/json',
      query: { address: address, key: key, region: 'br', language: 'pt-BR' },
      timeout: 15
    )
    return nil unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return nil unless data.is_a?(Hash) && data['status'] == 'OK'

    (data['results'] || []).first
  end
end
