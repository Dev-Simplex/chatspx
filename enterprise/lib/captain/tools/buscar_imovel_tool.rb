class Captain::Tools::BuscarImovelTool < Captain::Tools::BasePublicTool
  description 'Busca imóveis no acervo da Tozi (sistema Vista) e retorna até 5 opções com o link correto do site. ' \
              "Use status_tipo='venda' para comprar e status_tipo='locacao' para alugar. " \
              'Para proximidade geográfica, passe lat_min/lat_max/lng_min/lng_max vindos do buscar_localizacao.'

  param :status_tipo, type: 'string', desc: "'venda' para comprar, 'locacao' para alugar", required: true
  param :categoria, type: 'string', desc: 'Casa, Apartamento, Terreno, Sala Comercial, Kitnet. Vazio se não especificou.', required: false
  param :bairro, type: 'string', desc: 'Bairro em Sinop. Vazio se não especificou.', required: false
  param :valor_max, type: 'number', desc: 'Valor máximo: aluguel mensal pra locação, valor total pra venda.', required: false
  param :dormitorios, type: 'number', desc: 'Quantidade de dormitórios.', required: false
  param :lat_min, type: 'string', desc: 'Latitude mínima do bbox (do buscar_localizacao).', required: false
  param :lat_max, type: 'string', desc: 'Latitude máxima do bbox.', required: false
  param :lng_min, type: 'string', desc: 'Longitude mínima do bbox.', required: false
  param :lng_max, type: 'string', desc: 'Longitude máxima do bbox.', required: false

  VISTA_FIELDS = %w[Codigo Categoria Status Dormitorios Cidade Bairro ValorLocacao ValorVenda TituloSite].freeze
  META_KEYS = %w[total paginas pagina quantidade].freeze

  def perform(_tool_context, status_tipo:, categoria: nil, bairro: nil, valor_max: nil,
              dormitorios: nil, lat_min: nil, lat_max: nil, lng_min: nil, lng_max: nil)
    venda = status_tipo.to_s == 'venda'
    filter = { 'Cidade' => 'Sinop' }
    filter['Status'] = venda ? ['like', '%vend%'] : ['like', '%alug%']
    if valor_max.present?
      filter[venda ? 'ValorVenda' : 'ValorLocacao'] = ['', valor_max]
    end
    filter['Categoria'] = categoria if categoria.present?
    filter['Bairro'] = bairro if bairro.present?
    filter['Dormitorios'] = dormitorios if dormitorios.present?
    filter['Latitude'] = [lat_min, lat_max] if lat_min.present? && lat_max.present?
    filter['Longitude'] = [lng_min, lng_max] if lng_min.present? && lng_max.present?

    imoveis = fetch_vista(filter)
    return 'Nenhum imóvel encontrado com esses critérios.' if imoveis.blank?

    format_listings(imoveis, venda)
  rescue StandardError => e
    Rails.logger.warn("[BuscarImoveisTool] #{e.message}")
    'Não consegui buscar os imóveis agora.'
  end

  private

  def fetch_vista(filter)
    base = ENV.fetch('TOZI_VISTA_BASE_URL', 'https://toz19328-rest.vistahost.com.br')
    pesquisa = {
      fields: VISTA_FIELDS,
      filter: filter,
      order: { 'Codigo' => 'desc' },
      paginacao: { pagina: 1, quantidade: 5 }
    }
    resp = HTTParty.get(
      "#{base}/imoveis/listar",
      query: { key: ENV['TOZI_VISTA_API_KEY'].to_s, showtotal: 1, pesquisa: pesquisa.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: 15
    )
    return [] unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return [] unless data.is_a?(Hash)

    data.reject { |k, _| META_KEYS.include?(k) }.values.select { |v| v.is_a?(Hash) }
  end

  def format_listings(imoveis, venda)
    linhas = imoveis.first(5).map do |im|
      valor = venda ? "R$ #{im['ValorVenda']}" : "R$ #{im['ValorLocacao']}/mês"
      dorm = im['Dormitorios'].to_i.positive? ? "#{im['Dormitorios']} quartos, " : ''
      "#{im['Categoria']} #{dorm}no #{im['Bairro']}, #{valor}. #{build_url(im)}"
    end
    "Encontrei #{linhas.size} opção(ões):\n#{linhas.join("\n")}"
  end

  def build_url(im)
    "https://www.toziimoveis.com.br/#{slugify(im['TituloSite'])}-#{slugify(im['Cidade'])},#{im['Codigo']}"
  end

  def slugify(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
       .downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
  end
end
