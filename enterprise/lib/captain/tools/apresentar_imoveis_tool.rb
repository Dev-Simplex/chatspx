class Captain::Tools::ApresentarImoveisTool < Captain::Tools::BasePublicTool
  include Captain::Tools::ImoveisConhecidos

  description 'Apresenta ao cliente uma vitrine com as opções de imóvel que a busca retornou: cada opção vira um ' \
              'card com foto, resumo e um botão pra ele escolher, tudo numa mensagem só. ' \
              'Chame quando tiver MAIS DE UMA opção pra mostrar, logo depois de buscar, em vez de listar em texto. ' \
              'Serve pra o cliente ESCOLHER entre imóveis — pra aprofundar num imóvel que ele já escolheu, ' \
              'use a ferramenta de enviar fotos. Depois de montar a vitrine, espere a escolha dele.'

  param :codigos, type: 'string',
                  desc: 'Códigos dos imóveis a apresentar, separados por vírgula, exatamente como vieram no ' \
                        'resultado da busca DESTA conversa. Nunca invente um código, nunca reaproveite código de ' \
                        'outro imóvel ou de outra conversa.', required: true

  MAX_CARDS = 5 # freio de produto: vitrine é pra escolher, não pra despejar o acervo
  TITLE_LIMIT = 80
  SUBTITLE_LIMIT = 80
  BUTTON_LIMIT = 20
  VISTA_FIELDS = ['Codigo', 'ImoCodigo', 'Categoria', 'Status', 'Dormitorios', 'Bairro', 'BairroComercial',
                  'ValorVenda', 'ValorLocacao', 'AreaTotal', { 'Foto' => %w[Foto Destaque] }].freeze

  def perform(tool_context, codigos:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra montar a vitrine.' unless conversation

    # O canal que não desenha card mandaria só o texto da mensagem, sem foto e sem botão, e
    # sem falha nenhuma registrada — foi assim que o carrossel do WhatsApp saiu vazio no
    # Instagram. Quem monta pergunta ANTES de montar, e a IA recebe o que fazer no lugar.
    unless conversation.inbox.channel.supports_card_carousel?
      return 'Este canal não desenha vitrine de cards. Apresente as opções em texto mesmo, uma linha por imóvel ' \
             'com o link de cada um, e pergunte qual delas o cliente quer ver.'
    end

    pedidos = normaliza_codigos(codigos)
    return 'Preciso dos códigos dos imóveis que a busca desta conversa retornou.' if pedidos.empty?

    recusa = codigos_recusados(conversation, pedidos)
    return recusa if recusa

    cards = pedidos.filter_map { |codigo| build_card(codigo) }
    return 'Não consegui montar a vitrine desses imóveis — apresente as opções em texto.' if cards.empty?

    criar_mensagem(conversation, cards)
    "Montei a vitrine com #{cards.size} #{pluraliza(cards.size, 'imóvel', 'imóveis')}, cada um com foto e botão pra " \
      'escolher. NÃO repita a lista em texto e não mande fotos agora: espere o cliente tocar num card e trate a ' \
      'escolha dele.'
  rescue StandardError => e
    Rails.logger.warn("[ApresentarImoveisTool] #{e.message}")
    'Não consegui montar a vitrine agora.'
  end

  private

  def normaliza_codigos(codigos)
    codigos.to_s.split(',').map { |codigo| codigo.gsub(/\D/, '') }.reject(&:blank?).uniq.first(MAX_CARDS)
  end

  # Mesma trava do envio de fotos: só entra na vitrine código que apareceu numa busca desta
  # conversa. Sem busca registrada (conversa migrada), não há o que conferir e passa.
  def codigos_recusados(conversation, pedidos)
    vistos = codigos_conhecidos(conversation)
    return nil if vistos.empty?

    fora = pedidos - vistos
    return nil if fora.empty?

    "Os códigos #{fora.join(', ')} não apareceram na busca desta conversa. Use buscar_imovel primeiro e monte a " \
      'vitrine só com códigos que a busca retornou.'
  end

  # A lista de cards é AGNÓSTICA de canal: `content_attributes['cards']` é traduzido pelo
  # canal na hora do envio. O `content` é o texto que qualquer canal (e o painel) mostra —
  # sem ele, a mensagem apareceria vazia pro time.
  def criar_mensagem(conversation, cards)
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      content: resumo_texto(cards),
      content_attributes: { 'cards' => cards }
    )
  end

  def resumo_texto(cards)
    linhas = cards.map { |card| "• #{card['title']}#{card['subtitle'].present? ? " — #{card['subtitle']}" : ''}" }
    "Separei #{cards.size} #{pluraliza(cards.size, 'opção', 'opções')} pra você:\n#{linhas.join("\n")}"
  end

  def pluraliza(quantidade, singular, plural)
    quantidade == 1 ? singular : plural
  end

  def build_card(codigo)
    dados = fetch_detalhes(codigo)
    return nil if dados.blank?

    {
      'title' => titulo(dados, codigo).truncate(TITLE_LIMIT),
      'subtitle' => subtitulo(dados).truncate(SUBTITLE_LIMIT),
      'image_url' => foto_destaque(dados),
      # O título do botão carrega o código porque é ELE que volta como conteúdo da mensagem
      # quando o cliente toca: um "Ver fotos" solto deixaria a IA sem saber de qual imóvel.
      # O payload vai junto em content_attributes, no formato que o listener de automação lê.
      'button' => { 'title' => "Fotos do #{codigo}".truncate(BUTTON_LIMIT), 'payload' => "imovel:#{codigo}" }
    }.compact_blank
  end

  # Credenciais Vista por CONTA via concern (AccountIntegration -> custom_attributes -> ENV).
  def fetch_detalhes(codigo)
    resp = HTTParty.get(
      "#{vista_base_url}/imoveis/detalhes",
      query: { key: vista_api_key, imovel: codigo, pesquisa: { fields: VISTA_FIELDS }.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: 15
    )
    return {} unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    data.is_a?(Hash) && data['Codigo'].present? ? data : {}
  rescue StandardError => e
    Rails.logger.warn("[ApresentarImoveisTool] detalhes do #{codigo}: #{e.message}")
    {}
  end

  # A Meta exige título no card; sem categoria nem bairro cadastrados, o código sozinho
  # identifica o imóvel e o card continua de pé.
  def titulo(imovel, codigo)
    dormitorios = imovel['Dormitorios'].to_i
    partes = [imovel['Categoria'].to_s.strip.presence]
    partes << "#{dormitorios} quartos" if dormitorios.positive?
    bairro = imovel['Bairro'].to_s.strip.presence || imovel['BairroComercial'].to_s.strip.presence
    partes << "— #{bairro}" if bairro
    partes.compact.join(' ').presence || "Imóvel #{codigo}"
  end

  # Só o que o Vista traz (>0) — nunca inventa preço nem metragem.
  def subtitulo(imovel)
    venda = imovel['Status'].to_s.match?(/vend/i)
    valor = (venda ? imovel['ValorVenda'] : imovel['ValorLocacao']).to_f
    bits = []
    bits << (venda ? "R$ #{imovel['ValorVenda']}" : "R$ #{imovel['ValorLocacao']}/mês") if valor.positive?
    bits << "#{imovel['AreaTotal']} m²" if imovel['AreaTotal'].to_f.positive?
    bits.join(' · ')
  end

  # Destaque primeiro, como no envio de fotos: é a foto que o cliente reconhece do anúncio.
  def foto_destaque(imovel)
    fotos = imovel['Foto']
    return nil unless fotos.is_a?(Hash)

    fotos.values.sort_by { |foto| foto['Destaque'] == 'Sim' ? 0 : 1 }.filter_map { |foto| foto['Foto'] }.first
  end
end
