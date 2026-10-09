class Captain::Tools::EnviarFotosImovelTool < Captain::Tools::BasePublicTool
  include Captain::Tools::VistaImovelUrl
  include Captain::Tools::ImoveisConhecidos

  description 'Envia ao cliente as fotos reais de um imóvel pelo WhatsApp, em lotes de 3. ' \
              'Chame quando o cliente pedir fotos de um imóvel, informando o código (vem do resultado da busca). ' \
              'Se o cliente pedir mais fotos do mesmo imóvel, chame de novo com o mesmo código que envia as próximas 3. ' \
              'Pra o cliente ver TODAS as fotos, ofereça o link do imóvel (galeria completa no site) em vez de chamar isto em loop.'

  param :codigo, type: 'string',
                 desc: 'Código do imóvel que o cliente quer, exatamente como veio no resultado da busca DAQUELE imóvel. ' \
                       'Nunca reutilize o código de outro imóvel, nunca invente.', required: true

  BATCH = 3
  SEND_INTERVAL = 2 # segundos entre cada foto, pra o WhatsApp entregar uma por uma
  MAX_POR_IMOVEL = 9 # teto de fotos por imóvel no WhatsApp (3 lotes) — evita dilúvio; pra ver TODAS, a IA oferece o link da galeria
  HEAD_TIMEOUT = 3 # segundos por foto na conferência do carrossel
  TIPOS_FOTO_CARROSSEL = %w[image/jpeg image/png].freeze # o que a Meta aceita no header de imagem do card

  # Freio anti-rajada. O que precisa ser freado é a IA despejar imóveis que NINGUÉM pediu —
  # não o cliente pedir três de uma vez. A régua, então, é o TURNO: quantos imóveis distintos
  # já saíram desde a última fala do cliente. Se ele falar de novo, o turno reinicia e a
  # ferramenta libera — que é exatamente o que a recusa sempre prometeu e o código nunca cumpriu.
  #
  # O freio anterior era temporal (COOLDOWN de 90 s por CONVERSA) e não fazia essa distinção.
  # Medido na Tozi em 30 dias antes da troca: de 654 chamadas, **182 recusadas (27,8 %)**, e
  # **163 delas eram de um imóvel DIFERENTE** — ou seja, o cliente tinha pedido outro. Desfecho:
  # de 144 pares (conversa, imóvel) recusados em 85 conversas, **99 nunca receberam as fotos**,
  # nem da IA nem de humano. A mensagem de recusa dizia *"só envie de novo se ele pedir
  # explicitamente"* — mas o `return` já tinha acontecido e não existia caminho para "ele
  # pediu", então a IA prometia ("vou te mandar já já") e não tinha como entregar.
  MAX_IMOVEIS_POR_TURNO = 3
  # Conversa aberta por template pode ainda não ter fala do cliente. Sem essa âncora o turno é
  # a última hora — o freio continua existindo em vez de sumir no caso sem incoming.
  JANELA_SEM_FALA = 1.hour

  def perform(tool_context, codigo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra enviar as fotos.' unless conversation

    # Trava anti-alucinação: só envia foto de código que apareceu numa busca DESTA
    # conversa (buscar_imovel registra em codigos_buscados). Bloqueia a IA de mandar
    # foto de um código que ela supôs/lembrou (ex.: mandar prédio comercial por casa).
    # Vem ANTES do freio de turno: código inventado não pode ocupar vaga no teto.
    cod = codigo.to_s.gsub(/\D/, '')
    vistos = codigos_conhecidos(conversation)
    if vistos.any? && !vistos.include?(cod)
      return "O código #{cod} não apareceu na busca desta conversa. Use buscar_imovel primeiro e envie fotos SÓ de um código que a busca retornou — nunca de um código que você supôs ou lembrou de outro imóvel."
    end

    # O código que a IA cita pode ser o ImoCodigo — e o ImoCodigo de um imóvel é o Codigo de
    # OUTRO. Resolver pelo mapa da própria conversa antes de buscar (ver codigo_canonico).
    codigo = codigo_canonico(conversation, cod)

    # Depois do canônico, senão o mesmo imóvel citado pelos dois códigos contaria como dois.
    # Continuar o MESMO imóvel nunca é rajada — quem limita esse caso é o MAX_POR_IMOVEL.
    ja_no_turno = imoveis_do_turno(conversation)
    if ja_no_turno.size >= MAX_IMOVEIS_POR_TURNO && ja_no_turno.exclude?(codigo.to_s)
      return "Você já enviou fotos de #{ja_no_turno.size} imóveis desde a última mensagem do cliente. " \
             'NÃO mande de outro imóvel agora: apresente os que já foram e espere ele reagir. ' \
             'Assim que ele responder, você pode enviar de outro; se ele quiser ver vários de uma vez, ' \
             'ofereça o link da galeria no site.'
    end

    dados = fetch_detalhes(codigo)
    fotos = extract_fotos(dados)
    return 'Não encontrei fotos desse imóvel.' if fotos.blank?

    key = "fotos_offset_#{codigo}"
    sent = conversation.custom_attributes[key].to_i
    limite = [fotos.size, MAX_POR_IMOVEL].min
    if sent >= limite
      # Já enviou o teto (ou todas): NÃO reenvia do zero (evita foto repetida) — avança.
      return "Já enviei as fotos que dá pra mandar aqui do imóvel #{codigo}. Se o cliente quiser ver TODAS, ofereça o link do imóvel#{link_galeria(conversation, cod)} — a galeria completa está no site. NÃO reenvie as mesmas — avance a conversa (interesse, visita)."
    end

    # Opt-in por conta (assistant.config['fotos_carrossel']): manda as fotos numa ÚNICA
    # mensagem de carrossel interativo (1 foto por card + botões), em vez de N imagens.
    # Carrossel exige 2+ cards — com 1 foto restante cai no envio de imagem comum.
    return send_fotos_carrossel(conversation, dados, fotos, codigo, key, sent, limite) if carrossel_ativo?(conversation) && (limite - sent) >= 2

    batch = fotos[sent, BATCH] || []
    return 'Não encontrei fotos desse imóvel.' if batch.empty?

    send_batch(conversation, batch, codigo)
    new_sent = sent + batch.size
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(key => new_sent))

    if limite - new_sent > 0
      # Nao despejar fotos por conta propria (prende o lead num loop de midia): avancar a
      # conversa. Pra "ver todas", a IA oferece o LINK da galeria, nao mais fotos no chat.
      "Enviei #{batch.size} #{pluralizar_foto(batch.size)} do imóvel #{codigo}. Se o cliente quiser ver TODAS as fotos, " \
        "ofereça o link do imóvel#{link_galeria(conversation, cod)} — o site tem a galeria completa. " \
        'NÃO despeje mais fotos por conta própria; se ele pedir mais fotos aqui, chame esta ferramenta de novo.'
    elsif fotos.size > limite
      # Bateu o teto por imóvel: o site REALMENTE tem mais do que coube aqui, então oferecer a
      # galeria é oferta honesta.
      "Enviei #{new_sent} #{pluralizar_foto(new_sent)} do imóvel #{codigo} — é o máximo que dá pra mandar por aqui, " \
        "e o imóvel tem mais. Se o cliente quiser ver todas, ofereça o link#{link_galeria(conversation, cod)}. " \
        'Avance a conversa.'
    else
      # Mandou TUDO que existe cadastrado. A redação anterior dizia "fotos principais" e oferecia a
      # "galeria completa no site" também aqui — prometendo o que não existe. Num imóvel de foto
      # única a IA ainda falava no plural de uma coisa só, e o cliente ficava esperando o resto.
      "Enviei #{new_sent} #{pluralizar_foto(new_sent)} do imóvel #{codigo} — é tudo que ele tem cadastrado, " \
        'não há outras nem no site. Se o cliente pedir mais, diga com naturalidade que este imóvel só tem essa ' \
        'quantidade e ofereça o próximo passo (visita, ou imóveis parecidos). NÃO prometa mais fotos nem galeria.'
    end
  rescue StandardError => e
    Rails.logger.warn("[EnviarFotosImovelTool] #{e.message}")
    'Não consegui enviar as fotos agora.'
  end

  private

  # Imóveis distintos cujas fotos já saíram DESDE a última fala do cliente. A âncora é a
  # mensagem dele, não o relógio: é ela que separa "a IA está despejando" de "o cliente pediu".
  #
  # Lê o `property_code` que este mesmo tool carimba em toda foto e no carrossel — não precisa
  # de estado novo, e o rastro é o que de fato foi enviado, não o que se pretendeu enviar.
  def imoveis_do_turno(conversation)
    desde = conversation.messages.where(message_type: :incoming, private: false).maximum(:created_at)
    conversation.messages
                .where(message_type: :outgoing)
                .where(messages: { created_at: (desde || JANELA_SEM_FALA.ago).. })
                .filter_map { |m| m.additional_attributes&.[]('property_code').presence&.to_s }
                .uniq
  end

  # O retorno da tool é lido pelo MODELO: "1 fotos" vaza como concordância errada na fala dele.
  def pluralizar_foto(quantidade)
    quantidade == 1 ? 'foto' : 'fotos'
  end

  # O `urls_imoveis` guarda **Codigo E ImoCodigo apontando para a MESMA URL** (track_urls do
  # buscar_imovel), e essa URL termina no Codigo canônico. Isso importa porque os dois espaços
  # de código se cruzam: medido na Tozi, `4586` é o ImoCodigo da CASA de aluguel 4629 e, ao
  # mesmo tempo, o Codigo de um TERRENO à venda em outro bairro. Como o `/imoveis/detalhes`
  # resolve por Codigo, pedir fotos citando o ImoCodigo trazia o imóvel errado — a cliente da
  # conv 28684 pediu foto de uma casa e recebeu a foto de um terreno.
  #
  # Resolver pelo mapa da PRÓPRIA conversa devolve sempre o imóvel que a busca mostrou; sem
  # registro (busca antiga, conversa migrada), devolve o que veio e o comportamento é o de antes.
  def codigo_canonico(conversation, cod)
    url = conversation.custom_attributes.to_h['urls_imoveis'].to_h[cod.to_s].to_s
    url[/-(\d+)\z/, 1].presence || cod.to_s
  end

  # Entrega a URL canônica que a busca já registrou (urls_imoveis, alimentado pelo
  # buscar_imovel) em vez de mandar a IA lembrar dela: link remontado errado é apagado
  # pelo fix_property_links e o cliente recebe "veja no site" sem site nenhum.
  # Sem registro (busca antiga, conversa migrada), volta a orientação genérica.
  def link_galeria(conversation, cod)
    url = conversation.custom_attributes.dig('urls_imoveis', cod.to_s)
    url.present? ? ": #{url}" : ' (o mesmo que veio da busca)'
  end

  def fetch_detalhes(codigo)
    # Credenciais Vista por CONTA via concern (AccountIntegration -> custom_attributes -> ENV).
    # Além das fotos, traz os campos que montam a URL do site (modo ver_detalhes do carrossel).
    base = vista_base_url
    pesquisa = { fields: ['Codigo', 'ImoCodigo', 'Categoria', 'Dormitorios', 'Bairro', 'BairroComercial',
                          'Cidade', 'Status', { 'Foto' => %w[Foto Destaque] }] }
    resp = HTTParty.get(
      "#{base}/imoveis/detalhes",
      query: { key: vista_api_key, imovel: codigo, pesquisa: pesquisa.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: 15
    )
    return {} unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    data.is_a?(Hash) ? data : {}
  end

  def extract_fotos(dados)
    fotos = dados['Foto']
    return [] unless fotos.is_a?(Hash)

    # Destaque primeiro, depois o resto, na ordem das chaves
    fotos.values
         .sort_by { |f| [f['Destaque'] == 'Sim' ? 0 : 1] }
         .filter_map { |f| f['Foto'] }
  end

  # Duas condições, não uma: a conta opta pelo carrossel E o canal daquela conversa entrega
  # payload interativo. O carrossel é passthrough do WhatsApp Cloud; num canal que não lê a
  # chave (Instagram, WAHA, Messenger) a mensagem sai como o TEXTO do content — "📷 Carrossel:
  # 9 fotos do imóvel X" — sem foto e sem falha registrada, e a tool ainda devolve "enviei",
  # então a IA garante ao cliente que mandou. Medido na Tozi (conta 6, inbox 101 Instagram):
  # 9 chamadas, 0 imagem entregue, clientes respondendo "não apareceu" e "fotos não carrega".
  # Sem carrossel, o fluxo cai no envio foto a foto, que o Instagram entrega normalmente.
  def carrossel_ativo?(conversation)
    return false unless @assistant&.config&.[]('fotos_carrossel') == true

    conversation.inbox.channel.supports_interactive_payload?
  end

  # Carrossel de mídia interativo (2-10 cards, 1 foto por card) numa única mensagem, via
  # passthrough interactive_payload (WhatsappCloudService#send_raw_interactive, Graph v23+).
  # A Meta baixa a foto pela URL pública do Vista — sem Down.download aqui.
  # Botões por config da conta ('fotos_carrossel_botoes'): default = quick replies
  # (interesse/visita, geram resposta na conversa); 'ver_detalhes' = 1 botão CTA URL que
  # abre a página do imóvel no site (não gera resposta nem webhook). Meta não deixa
  # misturar os dois tipos no mesmo carrossel.
  # Obs.: card 'type' => 'cta_url' mesmo com quick_reply é o formato do exemplo oficial da
  # doc (validado ao vivo) — não trocar sem re-testar.
  def send_fotos_carrossel(conversation, dados, fotos, codigo, key, sent, limite)
    candidatas = fotos[sent, limite - sent] || []
    urls = candidatas.select { |url| foto_aceita_pela_meta?(url) }
    return send_fotos_sem_carrossel(conversation, urls, codigo, key, sent + candidatas.size) if urls.size < 2

    total = urls.size
    card_action = card_action_for(dados, codigo)
    cards = urls.each_with_index.map do |url, i|
      {
        'card_index' => i,
        'type' => 'cta_url',
        'header' => { 'type' => 'image', 'image' => { 'link' => url } },
        'body' => { 'text' => "Foto #{i + 1} de #{total} — imóvel #{codigo}" },
        'action' => card_action
      }
    end

    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      content: "📷 Carrossel: #{total} fotos do imóvel #{codigo}",
      additional_attributes: { 'property_code' => codigo },
      content_attributes: { 'interactive_payload' => {
        'type' => 'carousel',
        'body' => { 'text' => "Fotos do imóvel #{codigo} — desliza pro lado pra ver todas" },
        'action' => { 'cards' => cards }
      } }
    )

    conversation.update!(custom_attributes: conversation.custom_attributes.merge(key => sent + candidatas.size))

    "Enviei um carrossel com #{total} fotos do imóvel #{codigo}, com botões de interesse e visita. " \
      'Se o cliente quiser ver TODAS as fotos, ofereça o link do imóvel (galeria completa no site). ' \
      'NÃO reenvie as mesmas fotos — avance a conversa.'
  end

  # A Meta baixa a foto de cada card pela URL e, se UMA vier com Content-Type que ela não aceita,
  # recusa o carrossel INTEIRO (131053 "Media upload error") e o cliente não recebe nenhuma.
  # Caso real: Tozi, conv 43132 — 8 fotos image/jpeg e 1 servida pelo Vista como
  # binary/octet-stream. Conferir antes com HEAD e deixar de fora a que seria recusada.
  # Falha de rede ou timeout conta como reprovada: é a mesma foto que a Meta não conseguiria baixar.
  def foto_aceita_pela_meta?(url)
    resp = HTTParty.head(url, timeout: HEAD_TIMEOUT)
    resp.success? && TIPOS_FOTO_CARROSSEL.include?(resp.headers['content-type'].to_s.split(';').first.to_s.strip.downcase)
  rescue StandardError
    false
  end

  # Sobrou menos de 2 fotos aceitas — o carrossel não existe com 1 card. Com 1, vai pelo envio
  # avulso de sempre. Com nenhuma, o offset NÃO avança e o retorno diz à IA que nada saiu,
  # para ela não garantir ao cliente que mandou.
  def send_fotos_sem_carrossel(conversation, urls, codigo, key, novo_sent)
    if urls.empty?
      return "Não consegui enviar as fotos do imóvel #{codigo}: o site não entregou as imagens num formato que o WhatsApp aceita. " \
             "NÃO diga que enviou. Ofereça ao cliente o link do imóvel#{link_galeria(conversation, codigo)} para ver as fotos no site."
    end

    send_photo(conversation, urls.first, codigo)
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(key => novo_sent))
    "Enviei só 1 foto do imóvel #{codigo} — as outras não puderam ser enviadas por aqui. " \
      "Se o cliente quiser ver mais, ofereça o link do imóvel#{link_galeria(conversation, codigo)}. Avance a conversa."
  end

  def card_action_for(dados, codigo)
    if @assistant&.config&.[]('fotos_carrossel_botoes') == 'ver_detalhes' && (site_url = imovel_site_url(dados)).present?
      { 'name' => 'cta_url', 'parameters' => { 'display_text' => 'Ver detalhes', 'url' => site_url } }
    else
      { 'buttons' => [
        { 'type' => 'quick_reply', 'quick_reply' => { 'id' => "interesse-#{codigo}", 'title' => 'Tenho interesse' } },
        { 'type' => 'quick_reply', 'quick_reply' => { 'id' => "visita-#{codigo}", 'title' => 'Agendar visita' } }
      ] }
    end
  end

  # Mesma URL que a buscar_imovel entrega (módulo compartilhado) — respeita a trava de link.
  # Sem dados suficientes, retorna nil e o card cai nos quick replies.
  def imovel_site_url(dados)
    return nil if dados['Codigo'].blank?

    build_url(dados, dados['Status'].to_s.match?(/vend/i))
  rescue StandardError
    nil
  end

  # Quantas fotos vão, e a que imóvel pertencem, é o mesmo dos dois lados — muda só o
  # empacotamento. Onde o canal entrega várias imagens numa mensagem só (Instagram), o lote
  # vira UMA mensagem com N anexos: acaba a rajada de N mensagens com intervalo entre elas,
  # que prendia o lead num loop de mídia.
  def send_batch(conversation, urls, codigo)
    return send_photos_grouped(conversation, urls, codigo) if agrupa_fotos?(conversation) && urls.size >= 2

    # Uma por uma com intervalo: em rajada o bridge do WhatsApp entrega só a 1ª.
    urls.each_with_index do |url, i|
      send_photo(conversation, url, codigo)
      sleep(SEND_INTERVAL) if i < urls.size - 1
    end
  end

  def agrupa_fotos?(conversation)
    conversation.inbox.channel.supports_multi_image_message?
  end

  # Sem Down.download: a Meta busca cada foto pela URL pública do Vista, como o carrossel do
  # WhatsApp já faz. Além de poupar N downloads, tira do caminho o teto local de 15 MB do
  # `send_photo`, que é maior que os 8 MB por imagem que o Instagram aceita.
  def send_photos_grouped(conversation, urls, codigo)
    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      additional_attributes: { 'property_code' => codigo }
    )
    urls.each do |url|
      msg.attachments.build(account_id: conversation.account_id, file_type: :image, external_url: url)
    end
    msg.save!
  end

  def send_photo(conversation, url, codigo)
    io = Down.download(url, max_size: 15 * 1024 * 1024)
    # Anexo construido ANTES do save: o envio dispara no after_create_commit da mensagem,
    # entao criar o attachment depois (create! + create!) e corrida — o WhatsApp Cloud
    # recebia payload de texto com body vazio e recusava (text.body expected string).
    # property_code carimba a qual imovel a foto pertence: sem isso a foto e um outgoing
    # de conteudo vazio, indistinguivel no historico e no reply-context (o "esse e qual?").
    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      additional_attributes: { 'property_code' => codigo }
    )
    msg.attachments.build(
      account_id: conversation.account_id,
      file_type: :image,
      file: { io: io, filename: File.basename(URI.parse(url).path), content_type: 'image/jpeg' }
    )
    msg.save!
  end
end
