# Ficha do imóvel que o lead citou na própria mensagem, injetada como contexto do turno.
#
# O botão "Tenho interesse" do site abre o WhatsApp com um texto pronto que carrega o
# código do imóvel ("... (Ref: 9835)"), mas NÃO diz se ele é de venda ou de locação. Sem
# isso a triagem devolve "quer alugar ou comprar?" para um lead que já escolheu o imóvel —
# pergunta cuja resposta está no acervo, não com o cliente, e que na prática trava o lead
# (caso real: conversa 20282, imóvel só-venda, lead sumiu depois da pergunta).
#
# Resolve o código contra o Vista e devolve uma nota FACTUAL, no mesmo espírito do
# referral_note e do pin de localização: só dados, nenhuma instrução e nenhum exemplo que
# o modelo possa copiar. Com a ficha em mãos a IA transfere direto pro time certo — e
# também para de oferecer imóvel que já saiu do acervo.
#
# Opt-in por conta: exige o flag `property_ref_context` nos custom_attributes E a
# integração Vista configurada. Conta sem os dois é no-op silencioso.
class Captain::PropertyRefContextService
  include Captain::Tools::IntegrationCredentials

  # "(Ref: 9835)" é o formato que o site gera; aceita "Ref"/"Ref."/"Ref:" com espaçamento
  # variável. Exige 3+ dígitos para não casar número solto de conversa ("ref 12").
  REF_PATTERN = /\bref\.?\s*:?\s*(\d{3,6})\b/i
  FIELDS = %w[Codigo Categoria Status ValorVenda ValorLocacao Bairro Cidade Dormitorios].freeze
  CACHE_TTL = 6.hours
  HTTP_TIMEOUT = 8

  def initialize(message:)
    @message = message
    @account = message.try(:account)
  end

  # String com a ficha, ou nil quando não se aplica (o caminho comum: sem código na
  # mensagem, conta sem opt-in, imóvel inexistente). Nunca levanta: contexto é um extra,
  # não pode derrubar a montagem do turno.
  def note
    return unless @account && enabled? && @message.incoming?

    codigo = @message.content.to_s[REF_PATTERN, 1]
    return if codigo.blank?

    imovel = fetch_imovel(codigo)
    return if imovel.blank?

    format_note(imovel)
  rescue StandardError => e
    Rails.logger.warn("[PropertyRefContext] msg=#{@message&.id} #{e.class}: #{e.message}")
    nil
  end

  private

  # O concern resolve as credenciais a partir do assistant; aqui a origem é a conta da
  # mensagem. Mesma ordem de prioridade (AccountIntegration -> custom_attributes -> ENV).
  def tool_account
    @account
  end

  def enabled?
    @account.custom_attributes.present? &&
      ActiveModel::Type::Boolean.new.cast(@account.custom_attributes['property_ref_context']) &&
      vista_api_key.present?
  end

  def fetch_imovel(codigo)
    Rails.cache.fetch("captain:property_ref:#{@account.id}:#{codigo}", expires_in: CACHE_TTL) do
      pesquisa = { fields: FIELDS, filter: { 'Codigo' => codigo }, paginacao: { pagina: 1, quantidade: 1 } }
      resp = HTTParty.get(
        "#{vista_base_url}/imoveis/listar",
        query: { key: vista_api_key, pesquisa: pesquisa.to_json },
        headers: { 'Accept' => 'application/json' },
        timeout: HTTP_TIMEOUT
      )
      next {} unless resp.code == 200

      data = resp.parsed_response
      data = JSON.parse(data) if data.is_a?(String)
      next {} unless data.is_a?(Hash)

      data.values.find { |v| v.is_a?(Hash) && v['Codigo'].present? } || {}
    end.presence
  end

  def format_note(imovel)
    partes = ["código #{imovel['Codigo']}"]
    partes << imovel['Categoria'].to_s.strip.presence
    partes << disponibilidade(imovel)
    partes << valores(imovel).presence
    partes << local(imovel).presence
    partes << "#{imovel['Dormitorios']} dormitório(s)" if imovel['Dormitorios'].to_i.positive?

    "[Ficha do imóvel que o cliente citou, consultada no acervo: #{partes.compact.join(', ')}]"
  end

  # O que o cliente pode fazer com este imóvel — é a informação que evita a pergunta
  # "alugar ou comprar?". Status do Vista é texto livre ("Venda", "Aluguel", "Venda e
  # Aluguel", "Vendido", "Alugado"), então lê os dois lados e diz o que sobra.
  def disponibilidade(imovel)
    status = imovel['Status'].to_s
    return "INDISPONÍVEL no acervo (situação: #{status})" if status.match?(/vendid|alugad|reservad|suspens|inativ/i)

    venda = status.match?(/vend/i) || imovel['ValorVenda'].to_f.positive?
    locacao = status.match?(/alug|loca/i) || imovel['ValorLocacao'].to_f.positive?
    return 'disponível para venda e para locação' if venda && locacao
    return 'disponível para venda; não é imóvel de locação' if venda
    return 'disponível para locação; não está à venda' if locacao

    "situação no acervo: #{status.presence || 'não informada'}"
  end

  def valores(imovel)
    v = []
    v << "valor de venda #{format_brl(imovel['ValorVenda'])}" if imovel['ValorVenda'].to_f.positive?
    v << "aluguel #{format_brl(imovel['ValorLocacao'])}" if imovel['ValorLocacao'].to_f.positive?
    v.join(', ')
  end

  def local(imovel)
    [imovel['Bairro'].to_s.strip.presence, imovel['Cidade'].to_s.strip.presence].compact.join(', ')
  end

  def format_brl(valor)
    "R$ #{ActiveSupport::NumberHelper.number_to_delimited(valor.to_f.round, delimiter: '.')}"
  end
end
