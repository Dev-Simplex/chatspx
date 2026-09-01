class Captain::Tools::BuscarLocalizacaoTool < Captain::Tools::BasePublicTool
  description 'Geocodifica um endereço, bairro ou ponto de referência na cidade de atendimento ' \
              'e retorna as coordenadas (lat/lng) e o endereço formatado. Use quando precisar das ' \
              'coordenadas de um local pra passar pro buscar_imovel (filtro por proximidade).'

  param :local, type: 'string',
                desc: 'Endereço, bairro ou ponto de referência a localizar, conforme o cliente citou.',
                required: true

  # RubyLLM::Tool delega description da instância para a classe — override de instância pra
  # nomear a cidade REAL da conta. Sem config, geo_city é a cidade que estava fixa no código.
  def description
    "#{self.class.description} A cidade de atendimento é #{geo_city}."
  end

  def perform(_tool_context, local:)
    # Chave Google por CONTA via o concern IntegrationCredentials
    # (AccountIntegration -> custom_attributes -> ENV). Substitui a antiga custom
    # tool custom_buscar_localizacao_geocoding (chave saiu da URL pro account_integrations).
    key = google_maps_key
    return 'Busca de localização indisponível no momento.' if key.blank?

    result = geocode("#{local} #{geo_city}", key)
    return "Não achei a localização de \"#{local}\" em #{geo_city}." if result.blank?

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
