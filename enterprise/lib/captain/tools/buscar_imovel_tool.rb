class Captain::Tools::BuscarImovelTool < Captain::Tools::BasePublicTool
  include Captain::Tools::VistaImovelUrl

  description 'Busca imóveis no acervo da Tozi (sistema Vista) e retorna uma lista NUMERADA de até 5 opções, ' \
              'cada uma com o link correto do site. ' \
              "Use status_tipo='venda' para comprar e status_tipo='locacao' para alugar. " \
              'Cada opção já vem com nº de fotos, suítes, vagas de garagem e características (piscina, quintal, ' \
              'mobiliado, churrasqueira) — use SÓ esses dados retornados, nunca invente característica, foto ou link. ' \
              'A lista devolvida é o conjunto COMPLETO para aquele critério: imóvel que não está nela não existe, ' \
              'e apresentar imóvel fora dela é erro grave. ' \
              'Para proximidade geográfica, passe lat/lng (do buscar_localizacao OU da localização que o cliente enviou): ' \
              'retorna os mais próximos, ordenados pela distância em km.'

  param :status_tipo, type: 'string', desc: "'venda' para comprar, 'locacao' para alugar", required: true
  param :codigo, type: 'string',
                 desc: 'Código do imóvel que o cliente informar (do anúncio, da placa do imóvel, ou do site). Quando presente, busca o imóvel EXATO por esse código — ignore os outros filtros.', required: false
  param :categoria, type: 'string', desc: 'Casa, Apartamento, Terreno, Kitnet, Ponto Comercial, Prédio Comercial. Pra qualquer imóvel comercial (sala/ponto/loja/prédio comercial) use "Ponto Comercial". Vazio se não especificou.', required: false
  param :bairro, type: 'string', desc: 'Bairro/condomínio em Sinop. Vazio se não especificou.', required: false
  param :endereco, type: 'string',
                   desc: 'Rua, avenida ou logradouro, quando o cliente especificar. Estreita a busca dentro do bairro.', required: false
  param :valor_max, type: 'number', desc: 'Valor máximo: aluguel mensal pra locação, valor total pra venda.', required: false
  param :dormitorios, type: 'number', desc: 'Quantidade de dormitórios.', required: false
  param :piscina, type: 'boolean', desc: 'true SÓ quando o cliente pedir imóvel COM piscina — filtra pra retornar só os que têm.', required: false
  param :mobiliado, type: 'boolean',
                    desc: 'true SÓ quando o cliente pedir imóvel MOBILIADO/semimobiliado — filtra pra retornar só os que estão ' \
                          'cadastrados como mobiliados. Use em vez de dizer que vai verificar: a busca já responde.', required: false
  param :lat, type: 'string', desc: 'Latitude do ponto de referência (do buscar_localizacao ou da localização enviada pelo cliente).', required: false
  param :lng, type: 'string', desc: 'Longitude do ponto de referência.', required: false
  param :raio_km, type: 'number', desc: 'Só quando o cliente limitar a distância. Sem isso, lista os mais próximos.', required: false

  VISTA_FIELDS = %w[Codigo ImoCodigo Categoria Status Dormitorios Cidade Bairro BairroComercial ValorLocacao ValorVenda TituloSite
                    Condominio ValorCondominio ValorIptu AreaTotal AreaConstruida DescricaoWeb Latitude Longitude].freeze
  META_KEYS = %w[total paginas pagina quantidade].freeze

  # Veto de sanidade do geocoding: o que cair além disso do escritório não é da cidade
  # de atendimento, é homônimo de outro município (ver geocode_referencia).
  RAIO_URBANO_KM = 25

  # Quantos imóveis inspecionar (detalhes, 1 chamada por imóvel, com cache) quando o cliente
  # pede uma característica que o Vista NÃO aceita como filtro de listagem — hoje, mobiliado.
  TETO_INSPECAO = 60

  # Logradouro + número na descrição do anúncio. Em VENDA a régua do cliente é bairro apenas,
  # porque o endereço exato é o que um concorrente usa pra captar o imóvel do proprietário.
  LOGRADOURO = /\b(rua|avenida|av\.|travessa|alameda|rodovia|estrada|praça)\b[^,;.\n]{2,45}(,?\s*n[º°o]?\.?\s*\d{1,6})?/i

  def perform(tool_context, status_tipo:, categoria: nil, bairro: nil, endereco: nil, valor_max: nil,
              dormitorios: nil, piscina: nil, mobiliado: nil, lat: nil, lng: nil, raio_km: nil, codigo: nil)
    # Busca direta por CÓDIGO (placa/anúncio/site) — independe de venda/locação.
    if codigo.present?
      cod = codigo.to_s.gsub(/\D/, '')
      # O número que o cliente passa (placa/site/anúncio) às vezes é o Codigo interno,
      # às vezes o ImoCodigo do site — tenta os dois antes de dizer que não achou.
      achados = fetch_vista({ 'Codigo' => cod }, quantidade: 1)
      achados = fetch_vista({ 'ImoCodigo' => cod }, quantidade: 1) if achados.blank?
      return "Não achei nenhum imóvel com o código #{cod} no nosso sistema." if achados.blank?

      venda_cod = achados.first['Status'].to_s.match?(/vend/i)
      track_codigos(tool_context, achados)
      track_urls(tool_context, achados, venda_cod)
      return format_listings(achados, venda_cod, detalhado: true)
    end
    venda = status_tipo.to_s == 'venda'
    filter = { 'Cidade' => 'Sinop' }
    filter['Status'] = venda ? ['like', '%vend%'] : ['like', '%alug%']
    if valor_max.present?
      filter[venda ? 'ValorVenda' : 'ValorLocacao'] = ['', valor_max]
    end
    # Vista NÃO tem "Sala Comercial": os comerciais são "Ponto Comercial"/"Prédio Comercial".
    # Qualquer intenção comercial vira LIKE %Comercial% pra casar os dois; demais categorias, exato.
    if categoria.present?
      filter['Categoria'] = categoria.match?(/comercial|\bsala\b|\bloja\b/i) ? ['like', '%Comercial%'] : categoria
    end
    # match parcial: cliente diz "Aquarela", base tem "Residencial Aquarela Das Artes"
    filter['Bairro'] = ['like', "%#{bairro}%"] if bairro.present?
    filter['Endereco'] = ['like', "%#{endereco}%"] if endereco.present?
    filter['Dormitorios'] = dormitorios if dormitorios.present?
    # Piscina é característica (grupo carac) mas o Vista aceita como filtro de topo (testado).
    filter['Piscina'] = 'Sim' if piscina

    geo = lat.present? && lng.present?
    # O Vista compara Latitude/Longitude como STRING (lexicográfico) — com coordenadas
    # negativas o range nunca casa. Proximidade é calculada AQUI (Haversine), não lá.
    imoveis = fetch_vista(filter, quantidade: quantidade_para(geo, mobiliado), venda: venda)
    Rails.logger.info("[BuscarImovel] status=#{status_tipo} categoria=#{categoria.inspect} bairro=#{bairro.inspect} " \
                      "endereco=#{endereco.inspect} valor_max=#{valor_max.inspect} dorm=#{dormitorios.inspect} " \
                      "mobiliado=#{mobiliado.inspect} geo=#{geo} => #{imoveis.size} imoveis " \
                      "#{imoveis.first(5).map { |i| i['Codigo'] }.inspect}")
    if mobiliado
      candidatos = imoveis.size
      imoveis = imoveis.select { |im| detalhes_info(im['Codigo'])[:mobiliado] }
      return sem_mobiliado(candidatos) if imoveis.blank?
    end
    track_codigos(tool_context, imoveis)
    track_urls(tool_context, imoveis, venda)
    if imoveis.blank?
      # Só o fluxo normal (não-geo) amplia; o geo cai direto no "Nenhum...".
      ampliados = !geo && ampliar_sem_bairro(tool_context, filter, venda, bairro, endereco)
      return ampliados if ampliados.present?

      return 'Nenhum imóvel encontrado com esses critérios.'
    end
    return format_listings(imoveis, venda) unless geo

    format_by_distance(imoveis, venda, lat.to_f, lng.to_f, raio_km.presence&.to_f)
  rescue StandardError => e
    Rails.logger.warn("[BuscarImoveisTool] #{e.message}")
    'Não consegui buscar os imóveis agora.'
  end

  private

  # Mobiliado NÃO é filtro de listagem no Vista — pedir Caracteristicas.Mobiliado no /listar
  # devolve HTTP 400 ("campo não está disponível"). O dado só existe no /detalhes, um imóvel
  # por vez. Então a listagem traz um lote maior e o filtro é feito aqui, com o detalhes_info
  # (cacheado). Medido em 28/08: 4 dos 106 imóveis de locação são mobiliados — se este ramo
  # não existisse, a IA continuaria prometendo uma busca que ela não sabe fazer (conv 4809).
  def quantidade_para(geo, mobiliado)
    return 50 if geo
    return TETO_INSPECAO if mobiliado

    5
  end

  # Estado explícito, não lista vazia: o modelo precisa saber que a busca ACONTECEU e não
  # achou, senão ele preenche o silêncio.
  def sem_mobiliado(candidatos)
    "Conferi #{candidatos} imóvel(is) que batem no resto do critério e NENHUM está cadastrado " \
      'como mobiliado. Diga isso ao cliente como fato consultado (não como "vou verificar"), e ' \
      'ofereça as opções não mobiliadas ou o contato do consultor. Não prometa nova busca.'
  end

  def fetch_vista(filter, quantidade: 5, venda: false)
    base = vista_base_url
    # Ordena por PREÇO crescente (o mais em conta dentro do filtro primeiro), não por
    # Codigo desc (arbitrário, que escondia opções boas de código baixo — ex.: casa cód
    # 5474 barata no bairro pedido ficava fora do top 5). O Vista ordena ValorLocacao/
    # ValorVenda numericamente (testado). Geo re-ordena por distância depois.
    pesquisa = {
      fields: VISTA_FIELDS,
      filter: filter,
      order: { (venda ? 'ValorVenda' : 'ValorLocacao') => 'asc' },
      paginacao: { pagina: 1, quantidade: quantidade }
    }
    resp = vista_get("#{base}/imoveis/listar", { key: vista_api_key, showtotal: 1, pesquisa: pesquisa.to_json })
    return [] unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return [] unless data.is_a?(Hash)

    data.reject { |k, _| META_KEYS.include?(k) }.values.select { |v| v.is_a?(Hash) }
  end

  # 1 retry no GET do Vista: um timeout transitório fazia a IA dizer "não consegui / dificuldade
  # de acesso" num imóvel que EXISTE (conv 18960, 19099). Se a 2ª tentativa também falhar, o erro
  # sobe pro rescue do perform ("não consegui buscar agora"), não vira "não achei".
  def vista_get(url, query)
    HTTParty.get(url, query: query, headers: { 'Accept' => 'application/json' }, timeout: 15)
  rescue StandardError
    sleep(0.6)
    HTTParty.get(url, query: query, headers: { 'Accept' => 'application/json' }, timeout: 15)
  end

  # Registra na conversa os códigos que a busca retornou. A enviar_fotos_imovel só
  # manda foto de código que passou por aqui — trava a IA de inventar/lembrar código
  # de outro imóvel. Guarda os últimos 40 (rescue-safe: falha aqui não quebra a busca).
  def track_codigos(tool_context, imoveis)
    conv = find_conversation(tool_context&.state)
    return unless conv

    novos = imoveis.filter_map { |i| i['Codigo'].to_s.presence }
    return if novos.empty?

    vistos = Array(conv.custom_attributes['codigos_buscados']).map(&:to_s)
    conv.update!(custom_attributes: conv.custom_attributes.merge('codigos_buscados' => (vistos + novos).uniq.last(40)))
  rescue StandardError => e
    Rails.logger.warn("[BuscarImovel] track_codigos: #{e.message}")
  end

  # Guarda o mapa codigo/ImoCodigo -> URL canônica (build_url) na conversa (urls_imoveis),
  # pra o sanitizador de saída (fix_property_links) manter os links que a IA manda e remover
  # só os inventados. Sem isso, urls_imoveis fica vazio e TODO link da Tozi é apagado.
  #
  # Junto vai `dados_imoveis` (preço e bairro por código), que deixa o sanitizador conferir
  # se o link pertence ao imóvel descrito na frase — e não só se ele existe. É mapa IRMÃO,
  # não um novo formato do urls_imoveis: este é lido em dois lugares (fix_property_links e
  # enviar_fotos_imovel_tool), nenhum deles com spec, e um é o carrossel que está em
  # produção. Trocar o valor por hash quebraria os dois de uma vez.
  def track_urls(tool_context, imoveis, venda)
    conv = find_conversation(tool_context&.state)
    return unless conv

    novos = {}
    dados = {}
    imoveis.each { |im| registra_imovel(im, venda, novos, dados) }
    return if novos.empty?

    atuais = conv.custom_attributes
    mapas = { 'urls_imoveis' => mescla_mapa(atuais, 'urls_imoveis', novos),
              'dados_imoveis' => mescla_mapa(atuais, 'dados_imoveis', dados) }
    conv.update!(custom_attributes: atuais.merge(mapas))
  rescue StandardError => e
    # error, não warn (como no track_codigos): falhar aqui não degrada a busca, apaga o link
    # de todo imóvel da resposta. É invisível pro operador, então precisa aparecer no log.
    Rails.logger.error("[BuscarImovel] track_urls: #{e.message}")
  end

  # `|| {}` e não `fetch(chave, {})`: o default do fetch só entra quando a chave está
  # AUSENTE. Chave presente valendo nil (a API de custom_attributes aceita gravar isso)
  # devolve o nil, o merge estoura e o rescue do track_urls engole — os mapas param de ser
  # escritos sem sinal nenhum na tela, e sem urls_imoveis o fix_property_links não acha
  # código nenhum e apaga TODO link da Tozi. Guarda os 60 últimos.
  def mescla_mapa(atuais, chave, novos)
    (atuais[chave] || {}).merge(novos).to_a.last(60).to_h
  end

  # O imóvel entra nos dois mapas pelas duas chaves (Codigo e ImoCodigo), porque a IA cita
  # ora uma ora outra. Preço zero (imóvel só de locação numa busca de venda, ou vice-versa)
  # fica de fora do dados_imoveis: sem preço confiável, a guarda não deve opinar.
  def registra_imovel(imovel, venda, novos, dados)
    url = build_url(imovel, venda)
    preco = (venda ? imovel['ValorVenda'] : imovel['ValorLocacao']).to_f
    [imovel['Codigo'], imovel['ImoCodigo']].each do |k|
      next if k.to_s.strip.blank?

      novos[k.to_s] = url
      dados[k.to_s] = { 'preco' => preco, 'bairro' => imovel['Bairro'].to_s.strip } if preco.positive?
    end
  end

  # Fallback determinístico: quando a busca COM filtro de bairro/endereço vem vazia, refaz
  # UMA busca /listar (sem loop) removendo só o filtro de bairro/endereço — mantém cidade,
  # status, categoria, valor, dormitórios (e piscina). Devolve as opções com um header que
  # ORIENTA a IA (é diretiva, não fala pronta pro cliente) a apresentá-las como alternativas
  # fora do local pedido. Sem filtro de bairro/endereço não há o que ampliar (retorna nil).
  # NÃO é chamado no fluxo geo nem no por código. rescue próprio: falha aqui cai no
  # "Nenhum imóvel encontrado..." limpo, preservando o comportamento original.
  def ampliar_sem_bairro(tool_context, filter, venda, bairro, endereco)
    return if bairro.blank? && endereco.blank?

    imoveis = fetch_vista(filter.except('Bairro', 'Endereco'), quantidade: 5, venda: venda)
    return if imoveis.blank?

    track_codigos(tool_context, imoveis)
    track_urls(tool_context, imoveis, venda)
    ref = [bairro, endereco].reject(&:blank?).join('/')
    imoveis = anexar_distancia_da_referencia(imoveis, ref)
    format_listings(imoveis, venda, header: header_ampliado(ref, imoveis))
  rescue StandardError => e
    Rails.logger.warn("[BuscarImovel] ampliar_sem_bairro: #{e.message}")
    nil
  end

  # Quando a alternativa vem de OUTRO bairro, a distância até o que o cliente pediu deixa de
  # ser opinião. Conv 4809 (28/08): a IA ofereceu duas casas dizendo "essas ficam próximas ao
  # Centro" — estavam a 5,89 km e 8,96 km. O cálculo já existia (haversine + o campo dist_km
  # que o format_listings imprime); só faltava alguém geocodificar a referência pedida.
  def anexar_distancia_da_referencia(imoveis, referencia)
    ponto = geocode_referencia(referencia)
    return imoveis if ponto.nil?

    imoveis.map do |im|
      ilat = im['Latitude'].to_f
      ilng = im['Longitude'].to_f
      next im if ilat.zero? && ilng.zero?

      im.merge('dist_km' => haversine_km(ponto[:lat], ponto[:lng], ilat, ilng))
    end
  end

  def header_ampliado(ref, imoveis)
    com_dist = imoveis.any? { |im| im['dist_km'] }
    medida = com_dist ? " A distância de cada uma até #{ref} está na linha — use o número, não estime." : ''
    "Sem imóvel no critério exato (#{ref}). As opções abaixo são da mesma cidade e critério, " \
      'porém em OUTROS bairros: ofereça como alternativas fora do local pedido, deixando claro ' \
      'que não são do bairro/endereço solicitado — nunca encerre só com pergunta, apresente as ' \
      "opções concretas.#{medida}"
  end

  # Geocodifica a referência que o CLIENTE pediu, com veto de sanidade: o Google nunca devolve
  # "não achei" para um bairro que não conhece — devolve um homônimo de outra cidade. Medido em
  # 28/08 sobre os 259 bairros do acervo: 259 "resolveram" e 67 (26%) caíram a mais de 3 km dos
  # imóveis reais, sendo o pior a 518 km, em outro estado. `components=locality` quase não ajuda
  # (70 -> 67). Por isso o resultado só vale se cair dentro do raio urbano em volta do escritório.
  def geocode_referencia(termo)
    key = google_maps_key
    return nil if key.blank? || termo.blank?

    ponto = Rails.cache.fetch("captain:geo:#{tool_account&.id}:#{termo.downcase.strip}", expires_in: 30.days) do
      geocode_google(termo, key)
    end
    ponto if na_cidade?(ponto)
  rescue StandardError => e
    Rails.logger.warn("[BuscarImovel] geocode_referencia(#{termo}): #{e.message}")
    nil
  end

  def na_cidade?(ponto)
    return false if ponto.nil?

    office = office_coords
    haversine_km(office[:lat], office[:lng], ponto[:lat], ponto[:lng]) <= RAIO_URBANO_KM
  end

  def geocode_google(termo, key)
    resp = HTTParty.get('https://maps.googleapis.com/maps/api/geocode/json',
                        query: { address: "#{termo} #{geo_city}", key: key, region: 'br', language: 'pt-BR' },
                        timeout: 10)
    return nil unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return nil unless data.is_a?(Hash) && data['status'] == 'OK'

    loc = data.dig('results', 0, 'geometry', 'location')
    loc && { lat: loc['lat'].to_f, lng: loc['lng'].to_f }
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

  # A lista sai NUMERADA e com um rodapé fechando o mundo. Motivo medido (conv 4809, 28/08):
  # a IA apresentou três casas ao cliente e a terceira não existia — nem o bairro tinha casa,
  # nem o código que ela usou existe no Vista. A cliente escolheu justamente a inventada. A
  # trava do enviar_fotos_imovel barra a FOTO de código não-buscado, mas não barra a FALA.
  # Numerar dá ao modelo um conjunto fechado e contável pra copiar, em vez de um bloco de
  # texto de onde ele pode "continuar" a lista.
  def format_listings(imoveis, venda, header: nil, detalhado: false)
    linhas = imoveis.first(5).each_with_index.map { |im, idx| linha_imovel(im, idx, venda, detalhado) }
    "#{header || "Encontrei #{linhas.size} opção(ões):"}\n#{linhas.join("\n")}\n#{rodape_fechado(linhas.size)}"
  end

  def linha_imovel(imovel, idx, venda, detalhado)
    valor = venda ? "R$ #{imovel['ValorVenda']}" : "R$ #{imovel['ValorLocacao']}/mês"
    dorm = imovel['Dormitorios'].to_i.positive? ? "#{imovel['Dormitorios']} quartos, " : ''
    dist = imovel['dist_km'] ? " — a #{format('%.1f', imovel['dist_km'])} km da referência" : ''
    linha = "#{idx + 1}) (cód #{imovel['Codigo']}) #{imovel['Categoria']} #{dorm}no #{imovel['Bairro']}, #{valor}" \
            "#{format_area(imovel)}#{format_taxas(imovel)}#{format_extras(imovel['Codigo'])}" \
            "#{format_condominio(imovel)}#{dist}. #{build_url(imovel, venda)}"
    desc = detalhado ? descricao_limpa(imovel['DescricaoWeb'], venda: venda) : ''
    desc.present? ? "#{linha}\n#{desc}" : linha
  end

  def rodape_fechado(total)
    "São #{total} opção(ões) e não existem outras para este critério. Apresente SOMENTE imóvel " \
      'desta lista, sempre com o código dele. Se nada aqui servir, faça outra busca — nunca ' \
      'complete a lista de memória nem cite imóvel que não veio numa busca desta conversa.'
  end

  # Condomínio/IPTU só quando o Vista traz o valor (>0); nunca inventa. Taxa de lixo o Vista não tem.
  #
  # "TAXA de condomínio" por extenso, não só "condomínio": são DOIS campos distintos do Vista
  # (ValorCondominio = quanto se paga; Condominio = se o imóvel fica dentro de um condomínio
  # fechado) e a palavra sozinha os confundia na mesma linha. Ver format_condominio.
  def format_taxas(im)
    parts = []
    parts << "taxa de condomínio R$ #{im['ValorCondominio']}" if im['ValorCondominio'].to_f.positive?
    parts << "IPTU R$ #{im['ValorIptu']}" if im['ValorIptu'].to_f.positive?
    parts.any? ? " (#{parts.join(', ')})" : ''
  end

  # Vista diz se o imóvel está EM condomínio (campo Condominio). Antes a IA chutava
  # "condomínio fechado" pelo nome do bairro ("Residencial X") e errava a regra de
  # visita/chave (conv 19092); com o dado real ela acerta. Só mostra quando o Vista responde.
  #
  # Os rótulos são "FICA"/"NÃO fica" e não "em condomínio"/"avulso, sem condomínio" porque a
  # forma antiga colocava a palavra "condomínio" com dois sentidos na MESMA linha — a taxa
  # ("condomínio R$ 300") e o fato ("sem condomínio") — e o modelo passou a usar a taxa como
  # evidência do fato. Medido na conv 4809 (28/08): imóvel com ValorCondominio=300 e
  # Condominio="Nao" foi anunciado ao cliente como "em condomínio fechado", e a conduta de
  # visita ainda aplicou o caminho de visita acompanhada por cima do erro.
  def format_condominio(imovel)
    case imovel['Condominio'].to_s.strip.downcase
    when 'sim' then ' [FICA em condomínio fechado]'
    when 'nao', 'não' then ' [NÃO fica em condomínio fechado]'
    else ''
    end
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

  # Descrição do anúncio (DescricaoWeb) SEM telefone nem disclaimer — a IA não pode
  # vazar contato direto (fura o handoff). Só o corpo útil (o que está incluso, mobília,
  # condomínio incluso, etc.). Usada só no lookup por código (imóvel único).
  #
  # Em VENDA o logradouro também sai. A régua do cliente é: locação pode endereço completo,
  # venda só o bairro — porque endereço de imóvel à venda é o insumo que um concorrente usa
  # pra ir captar o imóvel direto com o proprietário. O campo `Endereco` nem é pedido ao
  # Vista (não está em VISTA_FIELDS), então a descrição era o único canal de texto: medido
  # em 28/08, 6 de 50 descrições de venda trazem logradouro. Fica a marca no lugar, em vez
  # de sumir em silêncio, pra o modelo saber que existe e foi omitido — e não preencher.
  def descricao_limpa(texto, venda: false)
    linhas = texto.to_s.split(/\r?\n/).reject do |l|
      l.match?(/contato|telefone|whats/i) ||
        l.match?(/\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]?\d{4}/) ||
        l.match?(/os valores.*sem pr[eé]vio aviso|mercado imobili/i)
    end
    txt = linhas.join("\n").gsub(/\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]?\d{4}/, '').gsub(/\n{3,}/, "\n\n").strip
    txt = txt.gsub(LOGRADOURO, '[endereço não divulgado em venda — informe só o bairro]') if venda
    txt.length > 600 ? "#{txt[0, 600].rstrip}…" : txt
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

  # Cacheado porque agora ele é chamado em lote: o filtro de mobiliado inspeciona até
  # TETO_INSPECAO imóveis por busca, e sem cache seriam 60 chamadas ao Vista a cada pergunta.
  # 6h é curto o bastante pra refletir cadastro novo e longo o bastante pra uma conversa
  # inteira reaproveitar. Chave por conta, porque cada conta tem o seu Vista.
  def detalhes_info(codigo)
    Rails.cache.fetch("captain:vista:detalhes:#{tool_account&.id}:#{codigo}", expires_in: 6.hours) do
      fetch_detalhes_info(codigo)
    end
  end

  def fetch_detalhes_info(codigo)
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

end
