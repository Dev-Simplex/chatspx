class Captain::Tools::EnviarFotosImovelTool < Captain::Tools::BasePublicTool
  include Captain::Tools::VistaImovelUrl

  description 'Envia ao cliente as fotos reais de um imóvel pelo WhatsApp, em lotes de 3. ' \
              'Chame quando o cliente pedir fotos de um imóvel, informando o código (vem do resultado da busca). ' \
              'Se o cliente pedir mais fotos do mesmo imóvel, chame de novo com o mesmo código que envia as próximas 3. ' \
              'Pra o cliente ver TODAS as fotos, ofereça o link do imóvel (galeria completa no site) em vez de chamar isto em loop.'

  param :codigo, type: 'string',
                 desc: 'Código do imóvel que o cliente quer, exatamente como veio no resultado da busca DAQUELE imóvel. ' \
                       'Nunca reutilize o código de outro imóvel, nunca invente.', required: true

  BATCH = 3
  SEND_INTERVAL = 2 # segundos entre cada foto, pra o WhatsApp entregar uma por uma
  COOLDOWN = 90 # segundos entre lotes de foto na MESMA conversa — freia a rajada multi-imóvel
  MAX_POR_IMOVEL = 9 # teto de fotos por imóvel no WhatsApp (3 lotes) — evita dilúvio; pra ver TODAS, a IA oferece o link da galeria

  def perform(tool_context, codigo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra enviar as fotos.' unless conversation

    # Freio anti-rajada: não deixa a IA despejar fotos de vários imóveis no mesmo turno
    # (era o "todas juntas"). O 1º lote da conversa sempre passa (ultimo=0).
    ultimo = conversation.custom_attributes['fotos_ultimo_envio_at'].to_i
    if ultimo.positive? && (Time.current.to_i - ultimo) < COOLDOWN
      return 'Você acabou de enviar fotos há pouco. NÃO envie mais fotos agora — avance a conversa e ' \
             'espere o cliente reagir. Só envie de novo se ele pedir explicitamente.'
    end

    # Trava anti-alucinação: só envia foto de código que apareceu numa busca DESTA
    # conversa (buscar_imovel registra em codigos_buscados). Bloqueia a IA de mandar
    # foto de um código que ela supôs/lembrou (ex.: mandar prédio comercial por casa).
    cod = codigo.to_s.gsub(/\D/, '')
    vistos = codigos_conhecidos(conversation)
    if vistos.any? && !vistos.include?(cod)
      return "O código #{cod} não apareceu na busca desta conversa. Use buscar_imovel primeiro e envie fotos SÓ de um código que a busca retornou — nunca de um código que você supôs ou lembrou de outro imóvel."
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

    # Envia uma por uma com intervalo: em rajada o bridge do WhatsApp entrega só a 1ª.
    batch.each_with_index do |url, i|
      send_photo(conversation, url, codigo)
      sleep(SEND_INTERVAL) if i < batch.size - 1
    end
    new_sent = sent + batch.size
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(
      key => new_sent, 'fotos_ultimo_envio_at' => Time.current.to_i
    ))

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

  # O que a busca DESTA conversa já devolveu, pelas duas chaves que a IA pode citar. Ler só
  # `codigos_buscados` recusava imóvel legítimo: o track_codigos grava apenas o Codigo e corta
  # em 40, enquanto o track_urls grava Codigo E ImoCodigo e corta em 60 — quando a IA cita o
  # ImoCodigo, ou quando a conversa é longa, o código real fica de fora e o cliente leva um
  # "não" que ele não vê. Somar os dois mapas não afrouxa a trava: código que busca nenhuma
  # retornou continua ausente dos dois.
  # O retorno da tool é lido pelo MODELO: "1 fotos" vaza como concordância errada na fala dele.
  def pluralizar_foto(quantidade)
    quantidade == 1 ? 'foto' : 'fotos'
  end

  def codigos_conhecidos(conversation)
    attrs = conversation.custom_attributes || {}
    mapa = attrs['urls_imoveis']
    Array(attrs['codigos_buscados']).map(&:to_s) + (mapa.is_a?(Hash) ? mapa.keys.map(&:to_s) : [])
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
    urls = fotos[sent, limite - sent] || []
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

    conversation.update!(custom_attributes: conversation.custom_attributes.merge(
      key => sent + total, 'fotos_ultimo_envio_at' => Time.current.to_i
    ))

    "Enviei um carrossel com #{total} fotos do imóvel #{codigo}, com botões de interesse e visita. " \
      'Se o cliente quiser ver TODAS as fotos, ofereça o link do imóvel (galeria completa no site). ' \
      'NÃO reenvie as mesmas fotos — avance a conversa.'
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
