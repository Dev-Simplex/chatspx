# Ficha do imóvel que o lead citou na própria mensagem, injetada como contexto do turno.
#
# O lead cita o imóvel de duas formas, e as duas trazem o código: o botão "Tenho interesse"
# do site abre o WhatsApp com um texto pronto ("... (Ref: 9835)"), e quem chega por fora
# COLA O LINK da página. Nenhuma das duas diz se o imóvel é de venda ou de locação, nem
# quanto custa. Sem a ficha, a triagem devolve "quer alugar ou comprar?" para quem já
# escolheu o imóvel (conversa 20282, imóvel só-venda, lead sumiu depois da pergunta) — e,
# pior, o imóvel vira assunto que a IA descreve de memória (conversa 41803: link do 9412 na
# primeira mensagem, aluguel afirmado R$ 2.400 num imóvel de R$ 3.200, zero busca no
# atendimento inteiro). Os dois são a mesma lacuna: o código chegou, o FATO não.
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

  # O OUTRO caminho, e o mais comum: o lead cola o LINK da página do imóvel. É a mesma
  # origem determinística do "(Ref:)" — o código está no endereço, não na interpretação do
  # modelo —, e sem ele a ficha não era montada e o imóvel virava assunto que a IA descreve
  # de memória (caso real: conversa 41803, link do 9412 na primeira mensagem, aluguel
  # afirmado R$ 2.400 num imóvel de R$ 3.200, sem uma única busca no atendimento).
  #
  # Formato: o mesmo que o VistaImovelUrl monta (`/imovel/<slug>-<codigo>`), com o código
  # no FIM do segmento — o slug é cosmético e o site resolve pelo número. Ancorar no fim é
  # o que impede casar número que faz parte do slug ("apto-123-quartos-9412" resolve 9412).
  LINK_PATTERN = %r{/imovel/[^\s/?#]*?(\d{3,6})(?:[/?#]|\z)}i

  # O TERCEIRO caminho: o código escrito por extenso depois da palavra "imóvel" ou "código". É o
  # texto pronto da comunidade da Tozi ("Vi na comunidade sobre o imóvel 10102 e quero saber
  # mais.") e o de quem digita o código da placa. Sem ele a ficha não saía, e a triagem perguntou
  # "alugar ou comprar?" para um imóvel só de venda (conversa 44350).
  #
  # Estreito de propósito, porque número solto em conversa de imóvel quase sempre é dinheiro ou
  # metragem: o número tem que vir COLADO na palavra (só "nº", "número", "#" ou ":" no meio), ter
  # de 4 a 6 dígitos e não ser seguido de unidade. "imóvel de 1500 reais", "imóvel 300 mil" e
  # "imóvel R$ 2500" não casam.
  CODIGO_PATTERN = /\b(?:im[oó]vel|c[oó]d(?:igo)?\.?)\s*(?:n[º°]\.?|n\.|n[uú]mero|\#|:)?\s*(\d{4,6})\b
                    (?!\s*(?:mil\b|reais\b|k\b|m²|m2\b|metros?\b|[.,]\d))/ix
  # ValorCondominio entra porque a ficha PASSA A SUBSTITUIR a busca: medido com N=6, quando
  # ela está no contexto o agente responde o preço direto e não chama mais o buscar_imovel.
  # Sem o condomínio aqui, a resposta fica correta e mais POBRE que a de hoje — some um
  # custo de R$ 731/mês da conta do inquilino. Ficha que substitui busca tem que empatar
  # com ela no que o cliente pergunta.
  FIELDS = %w[Codigo Categoria Status ValorVenda ValorLocacao ValorCondominio Bairro Cidade Dormitorios].freeze
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

    codigo = codigo_citado
    return if codigo.blank?

    imovel = fetch_imovel(codigo)
    return if imovel.blank?

    format_note(imovel)
  rescue StandardError => e
    Rails.logger.warn("[PropertyRefContext] msg=#{@message&.id} #{e.class}: #{e.message}")
    nil
  end

  private

  # "Ref:" primeiro por ser o formato explícito; o link é o fallback. Quem manda os dois na
  # mesma mensagem está falando do mesmo imóvel — não há caso em que a ordem mude a ficha.
  # O código escrito por extenso vem por último: os dois primeiros saem do site, este é texto
  # digitado, e só decide quando a mensagem não traz nenhuma origem determinística.
  def codigo_citado
    texto = @message.content.to_s
    texto[REF_PATTERN, 1].presence || codigo_do_link(texto) || texto[CODIGO_PATTERN, 1].presence
  end

  # Só link do domínio da PRÓPRIA conta. Sem essa amarra, link de portal ou de concorrente
  # com `/imovel/` no caminho viraria consulta ao nosso acervo, e o código de LÁ casaria com
  # um imóvel DAQUI — ficha errada com cara de certa, que é pior que ficha nenhuma.
  def codigo_do_link(texto)
    dominio = site_domain.to_s.strip
    return if dominio.blank?

    texto.scan(%r{https?://[^\s)\]]+}i).each do |url|
      next unless url.match?(/#{Regexp.escape(dominio)}/i)

      codigo = url[LINK_PATTERN, 1]
      return codigo if codigo.present?
    end
    nil
  end

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

  # Só o que o servidor CONFIRMOU entra no cache — inclusive a ausência confirmada (200 sem o
  # código), que é resposta legítima e vale as 6h. Falha de consulta não entra: antes, um não-200
  # de segundos era cacheado como `{}` e apagava a ficha pelas 6 horas seguintes, devolvendo o
  # imóvel à descrição de memória — exatamente a conv 41803 que motivou esta classe.
  #
  # O valor cacheado é envelopado (`consultado:`) em vez do imóvel cru: entrada gravada pelo
  # formato antigo simplesmente não casa e vira um miss, sem precisar de invalidação.
  def fetch_imovel(codigo)
    chave = "captain:property_ref:#{@account.id}:#{codigo}"
    cacheado = Rails.cache.read(chave)
    return cacheado[:imovel].presence if cacheado.is_a?(Hash) && cacheado[:consultado]

    imovel = consultar_imovel(codigo)
    Rails.cache.write(chave, { consultado: true, imovel: imovel }, expires_in: CACHE_TTL) unless imovel.nil?
    imovel.presence
  end

  # nil = a consulta falhou e não se sabe nada (desconhecido).
  # {}  = o servidor respondeu e não tem esse código (ausência confirmada).
  def consultar_imovel(codigo)
    pesquisa = { fields: FIELDS, filter: { 'Codigo' => codigo }, paginacao: { pagina: 1, quantidade: 1 } }
    resp = HTTParty.get(
      "#{vista_base_url}/imoveis/listar",
      query: { key: vista_api_key, pesquisa: pesquisa.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: HTTP_TIMEOUT
    )
    return nil unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return nil unless data.is_a?(Hash)

    data.values.find { |v| v.is_a?(Hash) && v['Codigo'].present? } || {}
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
    v << "condomínio #{format_brl(imovel['ValorCondominio'])}" if imovel['ValorCondominio'].to_f.positive?
    v.join(', ')
  end

  def local(imovel)
    [imovel['Bairro'].to_s.strip.presence, imovel['Cidade'].to_s.strip.presence].compact.join(', ')
  end

  # Arredondar servia enquanto a ficha só trazia venda e aluguel, que são inteiros no Vista.
  # Condomínio tem centavos (731,55) e arredondar publicaria 732 — número errado escrito
  # pela própria guarda contra número errado. Só quem tem centavos ganha as duas casas.
  def format_brl(valor)
    numero = valor.to_f
    return "R$ #{ActiveSupport::NumberHelper.number_to_delimited(numero.round, delimiter: '.')}" if (numero % 1).zero?

    ActiveSupport::NumberHelper.number_to_currency(numero, unit: 'R$ ', delimiter: '.', separator: ',')
  end
end
