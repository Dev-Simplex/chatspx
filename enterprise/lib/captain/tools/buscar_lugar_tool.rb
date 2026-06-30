class Captain::Tools::BuscarLugarTool < Captain::Tools::BasePublicTool
  description 'Busca lugares/comércios/pontos de referência por NOME em Sinop (ex: "Mercado Machado", "Unifasipe", "Hospital Regional"). ' \
              'Retorna a LISTA de unidades encontradas, cada uma com nome, endereço e coordenadas (lat/lng). ' \
              'Use quando o cliente citar um lugar como referência de proximidade — em especial redes com várias unidades. ' \
              'Mostre as opções, pergunte ao cliente QUAL ele quer, e então passe a lat/lng da escolhida pro buscar_imovel.'

  param :referencia, type: 'string',
                     desc: 'Nome do lugar/comércio/ponto de referência (ex: "Mercado Machado", "Unifasipe", "aeroporto").',
                     required: true

  FIELD_MASK = 'places.displayName,places.formattedAddress,places.location'.freeze

  def perform(_tool_context, referencia:)
    key = google_key
    return 'Busca de lugares indisponível no momento.' if key.blank?

    lugares = places_search(referencia, key)
    return "Não achei nenhum lugar com \"#{referencia}\" em Sinop." if lugares.blank?

    linhas = lugares.first(8).map.with_index(1) do |p, i|
      loc = p['location'] || {}
      "#{i}. #{p.dig('displayName', 'text')} — #{p['formattedAddress']} " \
        "[lat=#{loc['latitude']}, lng=#{loc['longitude']}]"
    end
    "Encontrei #{linhas.size} lugar(es) para \"#{referencia}\":\n#{linhas.join("\n")}\n" \
      'Pergunte ao cliente QUAL ele quer e use a lat/lng da escolhida no buscar_imovel.'
  rescue StandardError => e
    Rails.logger.warn("[BuscarLugarTool] #{e.message}")
    'Não consegui buscar os lugares agora.'
  end

  private

  # Chave Google por CONTA: o concern IntegrationCredentials#google_maps_key cobre
  # AccountIntegration (google) -> custom_attributes -> ENV. Último recurso (só desta
  # conta): reusa a chave embutida no endpoint do geocoding. Nunca pega a de outra conta.
  def google_key
    google_maps_key || geocoding_endpoint_key
  end

  def geocoding_endpoint_key
    acc = tool_account
    row = ActiveRecord::Base.connection.exec_query(
      "SELECT endpoint_url FROM captain_custom_tools WHERE slug = 'custom_buscar_localizacao_geocoding' AND account_id = #{acc&.id.to_i} LIMIT 1"
    ).first
    row && row['endpoint_url'].to_s[/key=([A-Za-z0-9_\-]+)/, 1]
  end

  def places_search(query, key)
    resp = HTTParty.post(
      'https://places.googleapis.com/v1/places:searchText',
      headers: {
        'Content-Type' => 'application/json',
        'X-Goog-Api-Key' => key,
        'X-Goog-FieldMask' => FIELD_MASK
      },
      body: { textQuery: "#{query} Sinop MT", languageCode: 'pt-BR', regionCode: 'BR' }.to_json,
      timeout: 15
    )
    return [] unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    data.is_a?(Hash) ? (data['places'] || []) : []
  end
end
