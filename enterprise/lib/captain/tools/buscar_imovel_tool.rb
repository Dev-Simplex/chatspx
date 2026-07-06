class Captain::Tools::BuscarImovelTool < Captain::Tools::BasePublicTool
  description 'Busca imóveis no acervo da Tozi (sistema Vista) e retorna até 5 opções com o link correto do site. ' \
              "Use status_tipo='venda' para comprar e status_tipo='locacao' para alugar. " \
              'Cada opção já vem com nº de fotos, suítes, vagas de garagem e características (piscina, quintal, ' \
              'mobiliado, churrasqueira) — use SÓ esses dados retornados, nunca invente característica, foto ou link. ' \
              'Para proximidade geográfica, passe lat/lng (do buscar_localizacao OU da localização que o cliente enviou): ' \
              'retorna os mais próximos, ordenados pela distância em km.'

  param :status_tipo, type: 'string', desc: "'venda' para comprar, 'locacao' para alugar", required: true
  param :codigo, type: 'string',
                 desc: 'Código do imóvel que o cliente informar (do anúncio, da placa do imóvel, ou do site). Quando presente, busca o imóvel EXATO por esse código — ignore os outros filtros.', required: false
  param :categoria, type: 'string', desc: 'Casa, Apartamento, Terreno, Sala Comercial, Kitnet. Vazio se não especificou.', required: false
  param :bairro, type: 'string', desc: 'Bairro/condomínio em Sinop. Vazio se não especificou.', required: false
  param :endereco, type: 'string',
                   desc: 'Rua, avenida ou logradouro, quando o cliente especificar (ex: "Mário Lago"). Estreita a busca dentro do bairro.', required: false
  param :valor_max, type: 'number', desc: 'Valor máximo: aluguel mensal pra locação, valor total pra venda.', required: false
  param :dormitorios, type: 'number', desc: 'Quantidade de dormitórios.', required: false
  param :piscina, type: 'boolean', desc: 'true SÓ quando o cliente pedir imóvel COM piscina — filtra pra retornar só os que têm.', required: false
  param :lat, type: 'string', desc: 'Latitude do ponto de referência (do buscar_localizacao ou da localização enviada pelo cliente).', required: false
  param :lng, type: 'string', desc: 'Longitude do ponto de referência.', required: false
  param :raio_km, type: 'number', desc: 'Só quando o cliente limitar a distância (ex: "até 2 km"). Sem isso, lista os mais próximos.', required: false

  VISTA_FIELDS = %w[Codigo ImoCodigo Categoria Status Dormitorios Cidade Bairro BairroComercial ValorLocacao ValorVenda TituloSite
                    ValorCondominio ValorIptu AreaTotal AreaConstruida Latitude Longitude].freeze
  META_KEYS = %w[total paginas pagina quantidade].freeze

  def perform(_tool_context, status_tipo:, categoria: nil, bairro: nil, endereco: nil, valor_max: nil,
              dormitorios: nil, piscina: nil, lat: nil, lng: nil, raio_km: nil, codigo: nil)
    # Busca direta por CÓDIGO (placa/anúncio/site) — independe de venda/locação.
    if codigo.present?
      cod = codigo.to_s.gsub(/\D/, '')
      achados = fetch_vista({ 'Codigo' => cod }, quantidade: 1)
      return "Não achei nenhum imóvel com o código #{cod} no nosso sistema." if achados.blank?

      return format_listings(achados, achados.first['Status'].to_s.match?(/vend/i))
    end
    venda = status_tipo.to_s == 'venda'
    filter = { 'Cidade' => 'Sinop' }
    filter['Status'] = venda ? ['like', '%vend%'] : ['like', '%alug%']
    if valor_max.present?
      filter[venda ? 'ValorVenda' : 'ValorLocacao'] = ['', valor_max]
    end
    filter['Categoria'] = categoria if categoria.present?
    # match parcial: cliente diz "Aquarela", base tem "Residencial Aquarela Das Artes"
    filter['Bairro'] = ['like', "%#{bairro}%"] if bairro.present?
    filter['Endereco'] = ['like', "%#{endereco}%"] if endereco.present?
    filter['Dormitorios'] = dormitorios if dormitorios.present?
    # Piscina é característica (grupo carac) mas o Vista aceita como filtro de topo (testado).
    filter['Piscina'] = 'Sim' if piscina

    geo = lat.present? && lng.present?
    # O Vista compara Latitude/Longitude como STRING (lexicográfico) — com coordenadas
    # negativas o range nunca casa. Proximidade é calculada AQUI (Haversine), não lá.
    imoveis = fetch_vista(filter, quantidade: geo ? 50 : 5)
    Rails.logger.info("[BuscarImovel] status=#{status_tipo} categoria=#{categoria.inspect} bairro=#{bairro.inspect} " \
                      "endereco=#{endereco.inspect} valor_max=#{valor_max.inspect} dorm=#{dormitorios.inspect} " \
                      "geo=#{geo} => #{imoveis.size} imoveis #{imoveis.first(5).map { |i| i['Codigo'] }.inspect}")
    return 'Nenhum imóvel encontrado com esses critérios.' if imoveis.blank?
    return format_listings(imoveis, venda) unless geo

    format_by_distance(imoveis, venda, lat.to_f, lng.to_f, raio_km.presence&.to_f)
  rescue StandardError => e
    Rails.logger.warn("[BuscarImoveisTool] #{e.message}")
    'Não consegui buscar os imóveis agora.'
  end

  private

  def fetch_vista(filter, quantidade: 5)
    base = vista_base_url
    pesquisa = {
      fields: VISTA_FIELDS,
      filter: filter,
      order: { 'Codigo' => 'desc' },
      paginacao: { pagina: 1, quantidade: quantidade }
    }
    resp = HTTParty.get(
      "#{base}/imoveis/listar",
      query: { key: vista_api_key, showtotal: 1, pesquisa: pesquisa.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: 15
    )
    return [] unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return [] unless data.is_a?(Hash)

    data.reject { |k, _| META_KEYS.include?(k) }.values.select { |v| v.is_a?(Hash) }
  end

  # Credenciais Vista por CONTA: vista_api_key / vista_base_url vêm do concern
  # IntegrationCredentials (AccountIntegration -> custom_attributes -> ENV).

  def format_by_distance(imoveis, venda, lat, lng, raio)
    com_geo = with_distances(imoveis, lat, lng)
    return 'Os imóveis encontrados não têm localização cadastrada — refaça a busca por bairro.' if com_geo.empty?

    com_geo.sort_by! { |im| im['dist_km'] }
    return format_listings(com_geo, venda, header: 'Mais próximos da referência:') if raio.blank?

    no_raio = com_geo.select { |im| im['dist_km'] <= raio }
    return format_listings(no_raio, venda) if no_raio.any?

    format_listings(com_geo.first(3), venda,
                    header: "Nenhum imóvel a até #{raio.round} km da referência. Os mais próximos são:")
  end

  # Imóvel sem lat/lng cadastrado (ou "0.0") fica fora do cálculo de proximidade.
  def with_distances(imoveis, lat, lng)
    imoveis.filter_map do |im|
      ilat = im['Latitude'].to_f
      ilng = im['Longitude'].to_f
      next if ilat.zero? && ilng.zero?

      im.merge('dist_km' => haversine_km(lat, lng, ilat, ilng))
    end
  end

  def haversine_km(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = (Math.sin(dlat / 2)**2) + (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlng / 2)**2))
    2 * 6371 * Math.asin(Math.sqrt(a))
  end

  def format_listings(imoveis, venda, header: nil)
    linhas = imoveis.first(5).map do |im|
      valor = venda ? "R$ #{im['ValorVenda']}" : "R$ #{im['ValorLocacao']}/mês"
      dorm = im['Dormitorios'].to_i.positive? ? "#{im['Dormitorios']} quartos, " : ''
      dist = im['dist_km'] ? " — a #{format('%.1f', im['dist_km'])} km da referência" : ''
      "(cód #{im['Codigo']}) #{im['Categoria']} #{dorm}no #{im['Bairro']}, #{valor}#{format_area(im)}#{format_taxas(im)}#{format_extras(im['Codigo'])}#{dist}. #{build_url(im, venda)}"
    end
    "#{header || "Encontrei #{linhas.size} opção(ões):"}\n#{linhas.join("\n")}"
  end

  # Condomínio/IPTU só quando o Vista traz o valor (>0); nunca inventa. Taxa de lixo o Vista não tem.
  def format_taxas(im)
    parts = []
    parts << "condomínio R$ #{im['ValorCondominio']}" if im['ValorCondominio'].to_f.positive?
    parts << "IPTU R$ #{im['ValorIptu']}" if im['ValorIptu'].to_f.positive?
    parts.any? ? " (#{parts.join(', ')})" : ''
  end

  # Área/metragem em m²: AreaTotal é a metragem do terreno/lote (essencial pra terreno);
  # AreaConstruida quando houver (imóvel já construído). Só mostra o que o Vista traz
  # (>0) — nunca inventa.
  def format_area(im)
    bits = []
    bits << "#{im['AreaTotal']} m²" if im['AreaTotal'].to_f.positive?
    bits << "#{im['AreaConstruida']} m² construídos" if im['AreaConstruida'].to_f.positive? && im['AreaConstruida'] != im['AreaTotal']
    bits.any? ? ", #{bits.join(', ')}" : ''
  end

  # Numa ÚNICA chamada ao Vista, traz o que a IA precisa saber pra NÃO alucinar:
  # nº de fotos, suítes, vagas de garagem e as características-chave (piscina, quintal,
  # mobiliado, churrasqueira). A IA passa a ver o que cada imóvel TEM e para de inventar
  # ("todas têm piscina", "não tem foto"). Falha de rede -> string vazia (não atrapalha).
  def format_extras(codigo)
    i = detalhes_info(codigo)
    return '' if i.empty?

    bits = []
    bits << (i[:fotos].positive? ? "#{i[:fotos]} fotos" : 'sem fotos')
    bits << "#{i[:suites]} suíte#{'s' if i[:suites] > 1}" if i[:suites].positive?
    bits << "#{i[:vagas]} vaga#{'s' if i[:vagas] > 1} de garagem" if i[:vagas].positive?
    bits << 'com piscina' if i[:piscina]
    bits << 'com quintal' if i[:quintal]
    bits << 'mobiliado' if i[:mobiliado]
    bits << 'com churrasqueira' if i[:churrasqueira]
    ", #{bits.join(', ')}"
  end

  def detalhes_info(codigo)
    resp = HTTParty.get(
      "#{vista_base_url}/imoveis/detalhes",
      query: { key: vista_api_key, imovel: codigo, pesquisa: { fields: ['Codigo', 'Suites', 'Vagas', { 'Foto' => %w[Foto] }, 'Caracteristicas'] }.to_json },
      headers: { 'Accept' => 'application/json' }, timeout: 10
    )
    return {} unless resp.code == 200

    d = resp.parsed_response
    d = JSON.parse(d) if d.is_a?(String)
    return {} unless d.is_a?(Hash)

    carac = d['Caracteristicas'].is_a?(Hash) ? d['Caracteristicas'] : {}
    { fotos: (d['Foto'].is_a?(Hash) ? d['Foto'].size : 0), suites: d['Suites'].to_i, vagas: d['Vagas'].to_i,
      piscina: sim?(carac['Piscina']), quintal: sim?(carac['Quintal']),
      mobiliado: sim?(carac['Mobiliado']), churrasqueira: sim?(carac['Churrasqueira']) }
  rescue StandardError
    {}
  end

  def sim?(val)
    val.to_s.strip.casecmp('sim').zero?
  end

  # O site da Tozi acha o imóvel pelo ImoCodigo (não pelo Codigo do Vista); o slug
  # é cosmético. Padrão observado: {finalidade}-{categoria}-{N}-dormitorios-{bairroComercial}-{cidade},{ImoCodigo}
  def build_url(im, venda)
    bairro = im['BairroComercial'].presence || im['Bairro']
    parts = [venda ? 'venda' : 'aluguel', slugify(im['Categoria'])]
    parts << "#{im['Dormitorios']}-dormitorios" if im['Dormitorios'].to_i.positive?
    parts << slugify(bairro) << slugify(im['Cidade'])
    id = im['ImoCodigo'].presence || im['Codigo']
    "https://www.#{site_domain}/#{parts.reject(&:blank?).join('-')},#{id}"
  end

  def slugify(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
       .downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
  end
end
