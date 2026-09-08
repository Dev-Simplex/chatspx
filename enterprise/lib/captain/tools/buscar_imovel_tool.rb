class Captain::Tools::BuscarImovelTool < Captain::Tools::BasePublicTool
  include Captain::Tools::VistaImovelUrl

  description 'Busca imóveis no acervo da Tozi (sistema Vista) e retorna uma lista NUMERADA de opções, ' \
              'cada uma com o link correto do site. ' \
              "Use status_tipo='venda' para comprar e status_tipo='locacao' para alugar. " \
              'Cada opção já vem com nº de fotos, suítes, vagas de garagem e características (piscina, quintal, ' \
              'mobiliado, churrasqueira) — use SÓ esses dados retornados, nunca invente característica, foto ou link. ' \
              'Apresentar imóvel que não veio na lista é erro grave. ' \
              'O retorno diz QUANTAS opções existem no critério e quantas estão listadas: quando há mais do que as ' \
              'listadas, não diga que são todas as disponíveis — pergunte a preferência do cliente e busque de novo ' \
              'com o filtro dela. ' \
              'Para proximidade geográfica, passe lat/lng (do buscar_localizacao OU da localização que o cliente enviou): ' \
              'retorna os mais próximos, ordenados pela distância em km.'

  param :status_tipo, type: 'string', desc: "'venda' para comprar, 'locacao' para alugar", required: true
  param :codigo, type: 'string',
                 desc: 'Código do imóvel que o cliente informar (do anúncio, da placa do imóvel, ou do site). Quando presente, busca o imóvel EXATO por esse código — ignore os outros filtros.', required: false
  param :categoria, type: 'string', desc: 'Casa, Apartamento, Terreno, Kitnet, Ponto Comercial, Prédio Comercial. Pra qualquer imóvel comercial (sala/ponto/loja/prédio comercial) use "Ponto Comercial". Vazio se não especificou.', required: false
  param :bairro, type: 'string', desc: 'Bairro/condomínio em Sinop. Vazio se não especificou.', required: false
  param :titulo, type: 'string',
                 desc: 'Título do anúncio, quando o cliente chega citando um. Portais de terceiros abrem a conversa ' \
                       'com o nome do anúncio entre aspas — passe esse texto aqui EXATAMENTE como ele veio, que a ' \
                       'busca acha o imóvel. Use sozinho: com bairro ou categoria junto, um nome escrito de forma ' \
                       'diferente da do cadastro faz a busca não achar nada.', required: false
  param :endereco, type: 'string',
                   desc: 'Rua, avenida ou logradouro, quando o cliente especificar. Estreita a busca dentro do bairro.', required: false
  param :valor_max, type: 'number', desc: 'Valor máximo: aluguel mensal pra locação, valor total pra venda.', required: false
  param :dormitorios, type: 'number', desc: 'Quantidade de dormitórios.', required: false
  param :piscina, type: 'boolean', desc: 'true SÓ quando o cliente pedir imóvel COM piscina — filtra pra retornar só os que têm.', required: false
  param :suite, type: 'boolean',
                desc: 'true SÓ quando o cliente pedir imóvel COM suíte (quarto com banheiro próprio) — filtra pra ' \
                      'retornar só os que têm. Quantos quartos ele quer continua indo em `dormitorios`: quem pede ' \
                      '"2 quartos sendo 1 suíte" quer os dois filtros juntos.', required: false
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
  #
  # 50 é TETO DA API, não escolha: acima disso o Vista responde
  # `400 — "O limite de resultados por página deve ser 50"` e a busca volta VAZIA. Com 60 aqui,
  # o ramo `mobiliado` nunca funcionou (era o "Conferi 0 imóvel(is)" que aparecia mesmo com
  # acervo cheio), e quando este valor passou a valer para a busca comum ele derrubou TODA
  # busca de imóvel em produção. Não subir sem antes conferir o limite da API.
  # Categorias como o Vista as escreve — conferidas no acervo em 08/09 (Terreno 38, Casa 31,
  # Kitnet 17, Apartamento 8, Chácara 3, e os três de unidade única). Servem só para reconhecer
  # a palavra no COMEÇO de um título de portal; não são filtro de busca. As compostas vêm
  # primeiro: "Conjunto de Kitnets" tem que casar antes de "Kitnet".
  CATEGORIAS_TITULO = ['Conjunto de Kitnets', 'Galpão Industrial', 'Ponto Comercial', 'Apartamento',
                       'Chácara', 'Kitnet', 'Terreno', 'Casa'].freeze

  TETO_INSPECAO = 50

  # Quantos imóveis a resposta APRESENTA. É diferente de quantos ela conhece: o cliente não
  # lê 17 opções numa mensagem, mas a IA precisa saber que existem 17 pra não dizer que são 5.
  MOSTRAR = 5

  # Logradouro + número na descrição do anúncio. Em VENDA a régua do cliente é bairro apenas,
  # porque o endereço exato é o que um concorrente usa pra captar o imóvel do proprietário.
  # O número é opcional E o "nº" antes dele também: "Rua das Palmeiras, 1234" tem que casar
  # inteiro, não só até a vírgula — senão a rua sai mascarada e o número fica na frase.
  LOGRADOURO = /\b(?:rua|avenida|av\.|travessa|alameda|rodovia|estrada|praça)\b[^,;.\n]{2,45}(?:,?\s*(?:n[º°o]?\.?\s*)?\d{1,6})?/i

  def perform(tool_context, status_tipo:, categoria: nil, bairro: nil, endereco: nil, valor_max: nil,
              dormitorios: nil, piscina: nil, mobiliado: nil, suite: nil, titulo: nil,
              lat: nil, lng: nil, raio_km: nil, codigo: nil)
    # Busca direta por CÓDIGO (placa/anúncio/site) — independe de venda/locação.
    if codigo.present?
      cod = codigo.to_s.gsub(/\D/, '')
      # O número que o cliente passa (placa/site/anúncio) às vezes é o Codigo interno,
      # às vezes o ImoCodigo do site — tenta os dois antes de dizer que não achou.
      achados = fetch_vista({ 'Codigo' => cod }, quantidade: 1)
      achados = fetch_vista({ 'ImoCodigo' => cod }, quantidade: 1) if achados.blank?
      return codigo_nao_encontrado(cod) if achados.blank?

      venda_cod = achados.first['Status'].to_s.match?(/vend/i)
      track_codigos(tool_context, achados)
      return format_listings(tool_context, achados, venda_cod, detalhado: true)
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
    # Título do anúncio. Portal de terceiro abre a conversa com o nome do anúncio, e ele é o
    # TituloSite do próprio cadastro: medido em 8 títulos reais de um portal, 6 acharam o
    # imóvel exato por aqui. Os 2 que não acharam eram anúncio de outra imobiliária no mesmo
    # portal — e é justamente esse caso que o retorno precisa nomear, em vez de devolver
    # "nenhum imóvel" e deixar a IA achar que o acervo está vazio.
    filter['TituloSite'] = ['like', "%#{titulo}%"] if titulo.present?
    filter['Endereco'] = ['like', "%#{endereco}%"] if endereco.present?
    filter['Dormitorios'] = dormitorios if dormitorios.present?
    # Piscina é característica (grupo carac) mas o Vista aceita como filtro de topo (testado).
    filter['Piscina'] = 'Sim' if piscina
    # Suítes é numérico: o Vista filtra por RANGE, e ['1','10'] é "pelo menos uma". Testado ao
    # vivo — `Suites: '1'` traria só as de exatamente uma e esconderia a casa de 2 suítes.
    filter['Suites'] = %w[1 10] if suite

    geo = lat.present? && lng.present?
    # O Vista compara Latitude/Longitude como STRING (lexicográfico) — com coordenadas
    # negativas o range nunca casa. Proximidade é calculada AQUI (Haversine), não lá.
    imoveis = fetch_vista(filter, quantidade: quantidade_para(geo, mobiliado), venda: venda)
    Rails.logger.info("[BuscarImovel] status=#{status_tipo} categoria=#{categoria.inspect} bairro=#{bairro.inspect} " \
                      "endereco=#{endereco.inspect} valor_max=#{valor_max.inspect} dorm=#{dormitorios.inspect} " \
                      "mobiliado=#{mobiliado.inspect} suite=#{suite.inspect} geo=#{geo} => #{imoveis.size} imoveis " \
                      "#{imoveis.first(5).map { |i| i['Codigo'] }.inspect}")
    if mobiliado
      candidatos = imoveis.size
      imoveis = imoveis.select { |im| detalhes_info(im['Codigo'])[:mobiliado] }
      return sem_mobiliado(candidatos) if imoveis.blank?
    end
    track_codigos(tool_context, imoveis)
    if imoveis.blank?
      # Título que não casa é caso próprio, e precisa ser dito com todas as letras: o anúncio
      # que o cliente viu pode ser de OUTRA imobiliária no mesmo portal. Sem isso o retorno
      # genérico faz a IA concluir que o acervo está vazio — e foi o que aconteceu quando ela
      # respondeu que não havia apartamento nenhum tendo 17 no cadastro.
      return sem_casar_pelo_titulo(tool_context, titulo, filter, venda) if titulo.present?

      # Só o fluxo normal (não-geo) amplia; o geo cai direto no "Nenhum...".
      ampliados = !geo && ampliar_sem_bairro(tool_context, filter, venda, bairro, endereco)
      return ampliados if ampliados.present?

      return 'Nenhum imóvel encontrado com esses critérios.'
    end
    return format_listings(tool_context, imoveis, venda) unless geo

    format_by_distance(tool_context, imoveis, venda, { lat: lat.to_f, lng: lng.to_f, raio: raio_km.presence&.to_f })
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
  # Pede o teto em todos os ramos, não só nos especiais. A busca comum pedia 5 ao Vista, e
  # como só se enxerga o que se pede, o total ficava indistinguível de "só existem 5" — foi
  # assim que a IA afirmou serem "todas as opções" tendo visto 5 de 17. O que continua sendo
  # apresentado ao cliente são as MOSTRAR primeiras; o resto serve pra saber o total.
  def quantidade_para(_geo, _mobiliado)
    TETO_INSPECAO
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

    # TETO e não 5: este ramo também passa pelo rodapé, e com 5 ele afirmaria que as
    # alternativas de outros bairros se esgotam nas primeiras.
    imoveis = fetch_vista(filter.except('Bairro', 'Endereco'), quantidade: TETO_INSPECAO, venda: venda)
    return if imoveis.blank?

    track_codigos(tool_context, imoveis)
    ref = [bairro, endereco].reject(&:blank?).join('/')
    imoveis = ordenar_alternativas(anexar_distancia_da_referencia(imoveis, ref))
    format_listings(tool_context, imoveis, venda, header: header_ampliado(ref, imoveis))
  rescue StandardError => e
    Rails.logger.warn("[BuscarImovel] ampliar_sem_bairro: #{e.message}")
    nil
  end

  # A ordem em que o Vista devolve é sempre a mesma, e o `format_listings` corta os MOSTRAR
  # primeiros — então TODO cliente cujo bairro não tem imóvel recebia exatamente as mesmas
  # opções. Medido em 03/09 pedindo cinco bairros diferentes (Pienza, Ipanema, Alvorada,
  # Girassol, Bandeirantes): os quatro mesmos imóveis nas cinco vezes, Bella Morada II e
  # Jardim Aurora sempre na frente. Em 30 dias isso virou 126 menções da IA a Bella Morada e
  # 119 a Aurora, contra 3 e 15 do time humano — e o acervo nem é concentrado ali: são 29
  # casas de locação espalhadas por ~20 bairros, lideradas por Santorini e Primaveras.
  #
  # Duas réguas, nesta ordem:
  #
  # 1. Distância, quando ela existe. O código já calculava `dist_km` e só a IMPRIMIA; usá-la
  #    para ordenar faz o cliente que pediu um bairro receber o que está perto DELE, que é o
  #    que ele quer. Vira critério em vez de rótulo.
  # 2. Sem distância (o geocoding erra 26% e é vetado pelo raio urbano), reveza por BAIRRO:
  #    um imóvel de cada bairro antes de repetir bairro. Não inventa proximidade que não foi
  #    medida, e ainda assim mostra a variedade real do acervo em vez dos mesmos dois.
  #
  # A ordem relativa do Vista é preservada dentro de cada grupo — `sort_by` e `group_by` são
  # estáveis em Ruby, então isto reordena sem embaralhar.
  # Distância PARCIAL ainda é distância. Medido no acervo de locação em 03/09: o geocoding do
  # bairro pedido resolve, 24 dos 29 imóveis têm coordenada e 5 não — exigir que TODOS
  # tivessem descartava a medida de 24 por causa de 5, e a lista voltava a ser a ordem do
  # Vista. Quem não tem coordenada vai para o fim, onde não atrapalha nem some.
  def ordenar_alternativas(imoveis)
    com, sem = imoveis.partition { |im| im['dist_km'] }
    return revezar_por_bairro(imoveis) if com.empty?

    com.sort_by { |im| im['dist_km'] } + revezar_por_bairro(sem)
  end

  def revezar_por_bairro(imoveis)
    grupos = imoveis.group_by { |im| im['Bairro'].to_s.strip.downcase }.values
    maior = grupos.map(&:size).max.to_i
    maior.times.flat_map { |i| grupos.filter_map { |g| g[i] } }
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

  # `ponto` agrupa lat/lng/raio: com eles soltos a lista de parametros passava de 5.
  def format_by_distance(tool_context, imoveis, venda, ponto)
    raio = ponto[:raio]
    com_geo = with_distances(imoveis, ponto[:lat], ponto[:lng])
    return 'Os imóveis encontrados não têm localização cadastrada — refaça a busca por bairro.' if com_geo.empty?

    com_geo.sort_by! { |im| im['dist_km'] }
    return format_listings(tool_context, com_geo, venda, header: 'Mais próximos da referência:') if raio.blank?

    no_raio = com_geo.select { |im| im['dist_km'] <= raio }
    return format_listings(tool_context, no_raio, venda) if no_raio.any?

    format_listings(tool_context, com_geo.first(3), venda,
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
  # O registro de URLs mora AQUI, e nao no ramo de busca, porque resolver o link e uma chamada
  # HTTP por imovel (VistaImovelUrl#site_api_link) e so este ponto sabe QUAIS imoveis vao ao
  # cliente. Registrar a lista inteira custava, medido na Tozi com cache limpo, 0,57s por imovel:
  # com o teto de 60 do PR #90 isso era ~34s de espera por busca, numa ferramenta que roda com o
  # cliente aguardando. Link que nao resolve nao entra em cache (`skip_nil`), entao esse custo se
  # repetia em toda busca. Aqui sao MOSTRAR chamadas, e o `linha_imovel` reaproveita o cache.
  # A lista completa continua indo para o `track_codigos`, que e barato e alimenta a trava de fotos.
  def format_listings(tool_context, imoveis, venda, header: nil, detalhado: false)
    track_urls(tool_context, imoveis.first(MOSTRAR), venda)
    linhas = imoveis.first(MOSTRAR).each_with_index.map { |im, idx| linha_imovel(im, idx, venda, detalhado) }
    "#{header || "Encontrei #{imoveis.size} opção(ões):"}\n#{linhas.join("\n")}\n#{rodape(linhas.size, imoveis.size)}"
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

  # "Não existem outras" só pode ser dito quando a lista mostrada É o acervo do critério.
  # Antes o rodapé afirmava isso sempre, e a busca comum pedia só 5 imóveis ao Vista: numa
  # conversa real de 01/09 havia 17 apartamentos para locação, a IA viu 5 e disse ao cliente
  # que eram "todas as opções disponíveis". A trava anti-invenção continua valendo nos dois
  # ramos — o que muda é parar de transformar truncamento em afirmação.
  def rodape(mostrados, total)
    return rodape_fechado(mostrados) if total <= mostrados

    rodape_parcial(mostrados, total)
  end

  # Antes de dizer que não achou pelo título, tenta desmontá-lo. Fica fora do `perform` porque
  # ele já está no teto de complexidade do rubocop.
  def sem_casar_pelo_titulo(tool_context, titulo, filter, venda)
    buscar_pelo_titulo_decomposto(tool_context, titulo, filter, venda).presence ||
      titulo_sem_correspondencia(titulo)
  end

  # O título que o cliente traz de um portal quase nunca é o `TituloSite` do cadastro: é o nome
  # que o portal MONTA, e ele é "Categoria + Bairro" — a mesma composição da URL do site da
  # Tozi (`casa-portal-do-servidor-sinop-9819`). Medido nas 13 buscas por título de 30 dias:
  # 9 não acharam, e as 9 seguem esse formato ("Casa Portal do Servidor", "Kitnet Jardim Terra
  # Rica", "CASA - RES. CANADÁ", "APARTAMENTO SONHALTO VIDEIRA"); as 4 que acharam eram o
  # TituloSite literal ("Kit net nova no Bairro Residencial Paris").
  #
  # Some-se que o campo é opcional e a Tozi não o preenche: 23 dos 50 imóveis de locação estão
  # com `TituloSite` VAZIO — inclusive o 9819, o imóvel desta conversa. Buscar só por ele
  # deixava a IA dizer que o anúncio "pode ser de outra imobiliária" sobre casa da própria casa.
  #
  # Aqui o título é desmontado e re-buscado por categoria + bairro. O bairro tende a ficar no
  # FIM, então o resto é tentado inteiro e depois encurtando pela esquerda — "CASA COM PISCINA
  # NO JARDIM IMPERIAL" só casa nos dois últimos termos, "CASA - RES. CANADÁ" só no último.
  def buscar_pelo_titulo_decomposto(tool_context, titulo, filter, venda)
    categoria, resto = decompor_titulo(titulo)
    return if resto.blank? && categoria.blank?

    imoveis = primeira_busca_que_acha(filter, categoria, resto, venda)
    return if imoveis.blank?

    track_codigos(tool_context, imoveis)
    format_listings(tool_context, imoveis, venda, header: header_por_titulo(titulo, imoveis))
  end

  # Duas passadas: primeiro exigindo a categoria, depois só o bairro. A segunda existe porque
  # o portal erra o tipo — "Kitnet Jardim Terra Rica" é o que o anúncio diz, e no Terra Rica só
  # há casa e terreno; mostrar os dois vale mais que negar o imóvel por causa do rótulo.
  #
  # NÃO existe terceira passada só com a categoria. Ela foi medida e descartada: sem bairro,
  # "CASA COM PISCINA NO JARDIM IMPERIAL" trazia 28 casas do acervo inteiro sob um cabeçalho
  # dizendo que o anúncio provavelmente era uma delas. Devolver o acervo é pior que dizer que
  # não achou.
  def primeira_busca_que_acha(filter, categoria, resto, venda)
    base = filter.except('TituloSite', 'Bairro', 'Categoria')
    termos = candidatos_de_bairro(resto)

    [categoria, nil].uniq.each do |cat|
      com_cat = cat.present? ? base.merge('Categoria' => cat) : base
      termos.each do |termo|
        achados = fetch_vista(com_cat.merge('Bairro' => ['like', "%#{termo}%"]),
                              quantidade: TETO_INSPECAO, venda: venda)
        return achados if achados.present?
      end
    end
    []
  end

  # "PISCINA JARDIM IMPERIAL" -> [a frase inteira, "JARDIM IMPERIAL", "IMPERIAL"]. Termo de uma
  # letra só não entra: casaria com meio acervo.
  def candidatos_de_bairro(resto)
    tokens = resto.to_s.split(/\s+/).reject { |p| p.length < 2 }
    return [] if tokens.empty?

    Array.new(tokens.size) { |i| tokens[i..].join(' ') }.reject(&:blank?).uniq
  end

  # A categoria vem no COMEÇO do título e é conferida contra a lista real do acervo, nunca
  # adivinhada. Pontuação e conectivo de sobra ("- RES.", "NO", "EM") saem do resto, senão o
  # `like` procura por eles dentro do nome do bairro e não acha nada.
  #
  # O `\b` nos conectivos NÃO é decoração: sem a fronteira de palavra, "na" seria removido de
  # dentro de "Canadá" e o bairro viraria "Cadá".
  def decompor_titulo(titulo)
    # O ponto entra no tr de propósito: em "RES." o `\b` do conectivo não casaria, porque
    # entre "." e o espaço não há fronteira de palavra — os dois são non-word.
    limpo = titulo.to_s.tr('-–—/|.,;', ' ').squeeze(' ').strip
    categoria = CATEGORIAS_TITULO.find { |c| limpo.match?(/\A#{Regexp.escape(c)}\b/i) }
    resto = categoria ? limpo.sub(/\A#{Regexp.escape(categoria)}\b/i, '') : limpo
    [categoria, sem_conectivos(resto)]
  end

  def sem_conectivos(resto)
    resto.gsub(/\b(no|na|em|de|do|da|res\.?|residencial|bairro|com)\b/i, ' ').squeeze(' ').strip
  end

  def header_por_titulo(titulo, imoveis)
    quantos = imoveis.size == 1 ? 'apareceu 1 imóvel' : "apareceram #{imoveis.size} imóveis"
    "Pelo título \"#{titulo}\" o cadastro não tinha nada, mas buscando pelo tipo e bairro que " \
      "ele descreve #{quantos}. É provável que o anúncio seja de um destes — confirme com o " \
      'cliente pelas características antes de tratar como o mesmo imóvel, e NÃO diga que o ' \
      'anúncio é de outra imobiliária.'
  end

  # Estado explícito, como o sem_mobiliado: a busca ACONTECEU e não achou aquele anúncio.
  # O que NÃO se pode concluir daqui é que não há imóvel — só que não há esse.
  # A ordem das explicações importa e estava invertida. "Pode ser de outra imobiliária" vinha
  # primeiro, e a IA repetia isso ao cliente como se fosse a conclusão — inclusive sobre imóvel
  # da própria Tozi (conv 33632). A causa mais comum é bem mais simples: o título é um campo
  # opcional que a Tozi não preenche, e 23 dos 50 imóveis de locação estão com ele VAZIO. Um
  # imóvel sem título cadastrado nunca casa aqui, exista ou não.
  def titulo_sem_correspondencia(titulo)
    "A busca pelo título \"#{titulo}\" não casou com nada, nem por tipo e bairro. Isso quase " \
      'sempre quer dizer que o imóvel está cadastrado sem título, não que ele não exista — ' \
      'metade do acervo de locação está assim. Pode ser também anúncio de outra imobiliária no ' \
      'mesmo portal, mas essa é a hipótese MENOS provável e você NÃO deve apresentá-la ao ' \
      'cliente como explicação. Peça a ele o que caracteriza o imóvel — tipo, bairro, faixa de ' \
      'valor, se é aluguel ou compra — e busque de novo por esses critérios. NÃO conclua nem ' \
      'diga que não temos o imóvel: esta busca foi só pelo nome do anúncio.'
  end

  def rodape_fechado(total)
    "São #{total} opção(ões) e não existem outras para este critério. Apresente SOMENTE imóvel " \
      'desta lista, sempre com o código dele. Se nada aqui servir, faça outra busca — nunca ' \
      'complete a lista de memória nem cite imóvel que não veio numa busca desta conversa.'
  end

  def rodape_parcial(mostrados, total)
    "Estas são #{mostrados} das #{total} opções que existem neste critério — há mais. NÃO diga " \
      'que são todas as disponíveis. Apresente SOMENTE imóvel desta lista, sempre com o código ' \
      'dele, e nunca complete a lista de memória. Se o cliente quiser ver outras, pergunte o que ' \
      'ele prefere (bairro, faixa de valor, nº de quartos) e busque de novo com esse filtro.'
  end

  # Condomínio/IPTU só quando o Vista traz o valor (>0); nunca inventa. Taxa de lixo o Vista não tem.
  #
  # "TAXA de condomínio" por extenso, não só "condomínio": são DOIS campos distintos do Vista
  # (ValorCondominio = quanto se paga; Condominio = se o imóvel fica dentro de um condomínio
  # fechado) e a palavra sozinha os confundia na mesma linha. Ver format_condominio.
  # O código que o cliente traz costuma vir de uma PLACA fotografada, e quem lê o número na
  # foto é o próprio modelo — que erra, e erra sem perceber. Conv 33099 (03/09): a placa dizia
  # 6767, ele leu 6763 e depois 6762, e as duas vezes anunciou ao cliente que o imóvel não
  # existia, inventando o porquê ("pode ser que já tenha sido alugada"). O imóvel estava no
  # acervo o tempo todo; só apareceu quando o cliente digitou o número.
  #
  # Duas leituras DIFERENTES da mesma imagem são a assinatura de leitura incerta. Medido em
  # 30 dias: 75 de 450 buscas por código voltam vazias, e em 6 conversas uma busca falhou e a
  # seguinte, com outro número, achou.
  #
  # O texto não podia seguir afirmando ausência: ele é o único sinal que o agente tem, e sem
  # ressalva vira "não temos esse imóvel". Aqui a régua é a MESMA que o transcritor de áudio
  # já aplica — dizer que a fonte é falível — mas sem fala pronta: descreve o estado e a
  # conduta esperada, e o agente escolhe as palavras.
  def codigo_nao_encontrado(cod)
    "Nenhum imóvel com o código #{cod} no acervo. ATENÇÃO: se esse número veio de uma FOTO " \
      '(placa, anúncio, print), a leitura pode ter sido sua e estar errada — dígito trocado é ' \
      'comum. Nesse caso NÃO afirme ao cliente que o imóvel não existe, não foi encontrado ou ' \
      'já foi alugado, e não invente motivo: peça que ele confirme o número, e busque de novo ' \
      'com o que ele responder. Só trate como inexistente o código que o PRÓPRIO cliente ' \
      'escreveu ou falou.'
  end

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
  # O rótulo negativo CONTINHA o positivo: "NÃO fica em condomínio fechado" tem dentro de si
  # a string "fica em condomínio fechado", e basta o modelo perder o "NÃO" para ler o oposto
  # do que o dado diz. Conv 33099 (03/09): o retorno trazia "[NÃO fica em condomínio fechado]"
  # e dois minutos depois a IA disse ao cliente que a casa era em condomínio fechado — e por
  # causa disso ofereceu agendar a visita, num imóvel de chave avulsa. O Vista é inequívoco:
  # Condominio="Nao", ValorCondominio="0".
  #
  # Agora a palavra que decide vem PRIMEIRO e é diferente em cada estado — AVULSO contra
  # CONDOMÍNIO FECHADO —, então ler pela metade não inverte o sentido. A menção a condomínio
  # no rótulo negativo é mantida de propósito: sem ela, volta a colisão com a TAXA
  # ("taxa de condomínio R$ 300") que o PR #75 tratou, em que o modelo usava o valor da taxa
  # como prova do fato.
  def format_condominio(imovel)
    case imovel['Condominio'].to_s.strip.downcase
    when 'sim' then ' [EM CONDOMÍNIO FECHADO]'
    when 'nao', 'não' then ' [AVULSO — fora de condomínio fechado]'
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
