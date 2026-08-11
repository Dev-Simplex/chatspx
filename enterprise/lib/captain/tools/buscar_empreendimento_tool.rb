class Captain::Tools::BuscarEmpreendimentoTool < Captain::Tools::BasePublicTool
  description 'Consulta o cadastro de empreendimentos da Tozi no sistema Vista/Loft (dados ao vivo). ' \
              'Sem nome, lista todos os empreendimentos disponíveis. Com nome (ou parte dele), traz os ' \
              'detalhes daquele empreendimento: localização, descrição, data de entrega e se está PRONTO ' \
              'pra morar ou ainda EM CONSTRUÇÃO/PLANTA. Use SÓ os dados retornados — nunca invente status, ' \
              'data ou descrição de empreendimento.'

  param :nome, type: 'string',
               desc: 'Nome (ou parte) do empreendimento que o cliente citou. Vazio = lista todos.',
               required: false

  BASE_FILTER = { 'Categoria' => 'Empreendimento' }.freeze
  LIST_FIELDS = %w[Codigo Empreendimento DataEntrega Situacao Bairro Cidade].freeze
  DETAIL_FIELDS = %w[Codigo Empreendimento DataEntrega Situacao Bairro Cidade DescricaoWeb DescricaoEmpreendimento AnoConstrucao].freeze
  META_KEYS = %w[total paginas pagina quantidade].freeze

  def perform(tool_context, nome: nil)
    buscado = nome.to_s.strip
    buscado.present? ? detalhe(tool_context, buscado) : lista(tool_context)
  rescue StandardError => e
    Rails.logger.warn("[BuscarEmpreendimento] #{e.message}")
    'Não consegui consultar os empreendimentos agora.'
  end

  private

  def detalhe(tool_context, nome)
    emps = fetch(BASE_FILTER.merge('Empreendimento' => ['like', "%#{nome}%"]), DETAIL_FIELDS)
    return "Não achei empreendimento com \"#{nome}\" no cadastro." if emps.blank?

    achados = emps.first(3)
    track_codigos(tool_context, achados)
    achados.map { |e| format_detail(e) }.join("\n\n")
  end

  def lista(tool_context)
    emps = fetch(BASE_FILTER, LIST_FIELDS)
    return 'Nenhum empreendimento cadastrado.' if emps.blank?

    track_codigos(tool_context, emps)
    "Empreendimentos da Tozi:\n" + emps.map { |e| "- #{e['Empreendimento']} (#{e['Bairro']}, #{e['Cidade']}) — #{fase(e)}" }.join("\n")
  end

  # Empreendimento também é registro do Vista e tem foto no mesmo campo dos imóveis,
  # então enviar_fotos_imovel funciona com o código dele. Mas ela só envia código que
  # apareceu numa busca DESTA conversa (trava anti-alucinação, em codigos_buscados) —
  # e quem preenchia isso era só a buscar_imovel. Sem registrar aqui, apresentar
  # empreendimento com foto falhava justamente nas conversas que já tinham buscado
  # imóvel antes.
  def track_codigos(tool_context, emps)
    conv = find_conversation(tool_context&.state)
    return unless conv

    novos = Array(emps).filter_map { |e| e['Codigo'].to_s.presence }
    return if novos.empty?

    vistos = Array(conv.custom_attributes['codigos_buscados']).map(&:to_s)
    conv.update!(custom_attributes: conv.custom_attributes.merge('codigos_buscados' => (vistos + novos).uniq.last(40)))
  rescue StandardError => e
    Rails.logger.warn("[BuscarEmpreendimento] track_codigos: #{e.message}")
  end

  def fetch(filter, fields)
    # O Vista limita a 50 resultados por página (o cadastro de empreendimentos cabe nisso).
    pesquisa = { fields: fields, filter: filter, paginacao: { pagina: 1, quantidade: 50 } }
    resp = HTTParty.get(
      "#{vista_base_url}/imoveis/listar",
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

  # Pronto pra morar vs em construção/planta pela DataEntrega (aceita YYYY-MM-DD e DD/MM/YYYY).
  def fase(emp)
    d = parse_date(emp['DataEntrega'])
    return d > Date.today ? 'em construção / na planta' : 'pronto pra morar' if d

    emp['Situacao'].to_s.strip.presence || 'situação a confirmar'
  end

  def parse_date(str)
    s = str.to_s.strip
    return nil if s.empty?

    if s =~ %r{\A(\d{2})/(\d{2})/(\d{4})\z}
      Date.new(::Regexp.last_match(3).to_i, ::Regexp.last_match(2).to_i, ::Regexp.last_match(1).to_i)
    else
      Date.parse(s)
    end
  rescue StandardError
    nil
  end

  def format_detail(emp)
    desc = emp['DescricaoWeb'].to_s.strip.presence || emp['DescricaoEmpreendimento'].to_s.strip.presence
    entrega = emp['DataEntrega'].to_s.strip.presence
    linhas = [
      "Empreendimento: #{emp['Empreendimento']} (código #{emp['Codigo']})",
      "Localização: #{emp['Bairro']}, #{emp['Cidade']}",
      "Situação: #{fase(emp)}#{entrega ? " — entrega #{entrega}" : ''}"
    ]
    linhas << "Sobre: #{desc}" if desc
    linhas.join("\n")
  end
end
