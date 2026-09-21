# Extrai as afirmações FACTUAIS de uma fala do agente, tipadas, e diz o que se espera de cada
# uma dada a evidência que existia no atendimento naquele instante.
#
# A asserção de um cenário não é "o preço bateu". A mesma fala da conv 41803 afirma preço,
# quartos, suíte e vagas — quatro fatos, todos sobre um imóvel que nenhuma busca devolveu.
# Assertar só o preço deixaria três invenções passarem no verde.
#
# Duas CLASSES, e elas se provam de formas diferentes:
#
#   - `imovel`: o que o imóvel É (preço, quartos, suíte, vaga, área). Precisa de FONTE — busca
#     ou ficha. Sem fonte que cubra o campo, é invenção;
#   - `acao`: o que o agente FEZ (mandei as fotos, mandei o pin). Prova-se pela própria
#     ferramenta de ação — mas só se ela confirmar que a ação ACONTECEU e com o mesmo conteúdo.
class Spx::Harness::Afirmacoes
  PADROES_IMOVEL = {
    'preco' => /R\$\s*([\d.]+(?:,\d{2})?)|\b([\d.]+(?:,\d{2})?)\s*reais\b/i,
    'dormitorios' => /\b(\d{1,2})\s*(?:quartos?|dormit[óo]rios?)\b/i,
    'suites' => /\b(\d{1,2})\s*su[íi]tes?\b/i,
    'vagas' => /\b(\d{1,2})\s*vagas?\b/i,
    'area' => /\b([\d.]+)\s*m²/i,
    'codigo' => /\b(?:c[óo]d(?:igo)?\.?|im[óo]vel|ref\.?)\s*:?\s*(\d{3,6})\b/i
  }.freeze

  ENVIO = /\b(?:mandei|enviei|segue[m]?|te\s+mand\w+|acabei\s+de\s+mandar)\b/i

  PADROES_ACAO = {
    'fotos_enviadas' => { alvo: /\bfotos?\b/i, tool: 'enviar_fotos_imovel' },
    'localizacao_enviada' => { alvo: /\b(?:localiza[çc][ãa]o|pin|mapa)\b/i, tool: 'enviar_localizacao_imovel' }
  }.freeze

  # Ferramentas que produzem evidência SOBRE O IMÓVEL. Resumo, handoff e observação não
  # comprovam preço nenhum — é por isso que a lista é por NOME e não "qualquer tool".
  FONTES_DE_EVIDENCIA = %w[buscar_imovel buscar_empreendimento apresentar_imoveis
                           consultar_chave_imovel buscar_unidades].freeze

  # Campo do Vista -> tipo de afirmação. Vem do que a ficha do PropertyRefContextService
  # REALMENTE traz (a constante FIELDS de lá): Codigo, Categoria, Status, ValorVenda,
  # ValorLocacao, ValorCondominio, Bairro, Cidade, Dormitorios.
  #
  # Repare no que NÃO existe nessa lista: suíte, vaga e área. Não é omissão desta tabela — a
  # ficha não pede esses campos ao Vista. Logo, um agente que só tem a ficha NUNCA tem como
  # saber quantas suítes o imóvel tem: afirmar é inventar, sempre. É o motivo estrutural de
  # duas das quatro afirmações da conv 41803 serem bloqueio, e não uma escolha de cenário.
  FICHA_PARA_TIPO = {
    'Codigo' => 'codigo',
    'ValorLocacao' => 'preco',
    'ValorVenda' => 'preco',
    'Dormitorios' => 'dormitorios'
  }.freeze

  # A ferramenta de ação pode rodar no mesmo segundo da fala, antes ou depois (a IA promete e a
  # tool cumpre, ou a tool roda e a IA narra). Janela em vez de ordem estrita.
  JANELA_ACAO = 120

  class << self
    def extrair(texto)
      imovel = PADROES_IMOVEL.flat_map do |tipo, rx|
        texto.to_s.scan(rx).filter_map do |casado|
          valor = normalizar(tipo, Array(casado).compact.first)
          { 'classe' => 'imovel', 'tipo' => tipo, 'valor' => valor } if valor
        end
      end
      (imovel + acoes(texto)).uniq
    end

    def acoes(texto)
      return [] unless texto.to_s.match?(ENVIO)

      PADROES_ACAO.filter_map do |tipo, cfg|
        next unless texto.match?(cfg[:alvo])

        { 'classe' => 'acao', 'tipo' => tipo,
          'quantidade' => texto[/\b(\d{1,2})\s*fotos?\b/i, 1]&.to_i,
          'codigo' => texto[/\b(?:c[óo]d(?:igo)?\.?|im[óo]vel|ref\.?)\s*:?\s*(\d{3,6})\b/i, 1] }.compact
      end
    end

    # O veredito de UMA afirmação: [esperado, motivo].
    def esperado(afirmacao, chamadas, instante, ficha: nil)
      return acao(afirmacao, chamadas, instante) if afirmacao['classe'] == 'acao'

      imovel(afirmacao, chamadas, instante, ficha)
    end

    def evidencia_antes(chamadas, instante)
      anteriores = Array(chamadas).select do |c|
        FONTES_DE_EVIDENCIA.include?(c['tool'].to_s) && c['em'].to_s < instante.to_s
      end
      anteriores.pluck('tool')
    end

    # Os valores que a ficha oferece para um tipo de afirmação. Lista, e não valor único, porque
    # um mesmo imóvel pode estar à venda E para locação: uma fala de "R$ 3.200" sem dizer qual é
    # compatível com qualquer um dos dois, e escolher um por conta própria inventaria contradição.
    def valores_da_ficha(ficha, tipo)
      return [] unless ficha.is_a?(Hash)

      campos = ficha.select { |campo, _| FICHA_PARA_TIPO[campo.to_s] == tipo }
      valores = campos.values.map { |valor| tipo == 'codigo' ? valor.to_s : valor.to_f }
      valores.reject { |valor| valor.is_a?(Float) ? valor.zero? : valor.blank? }
    end

    private

    def imovel(afirmacao, chamadas, instante, ficha)
      return ['conferir_contra_busca', 'houve busca antes da fala'] if evidencia_antes(chamadas, instante).any?

      candidatos = valores_da_ficha(ficha, afirmacao['tipo'])
      return ['bloquear', 'nenhuma fonte cobre este campo'] if candidatos.empty?
      return ['permitir', 'a ficha confirma'] if candidatos.include?(comparavel(afirmacao))

      ['bloquear', "a ficha diz #{candidatos.join(' ou ')}, a fala diz #{afirmacao['valor']}"]
    end

    def comparavel(afirmacao)
      afirmacao['tipo'] == 'codigo' ? afirmacao['valor'].to_s : afirmacao['valor'].to_f
    end

    # `status: 'ok'` NÃO prova que a ação aconteceu. Medido na conv 19863: a enviar_fotos_imovel
    # devolve 'ok' também quando a trava anti-alucinação BARRA o envio ("o código não apareceu
    # na busca") e quando o cooldown barra ("NÃO envie mais fotos agora"). Só o conteúdo do
    # retorno distingue envio de recusa — e é por isso que este método lê o texto.
    def acao(afirmacao, chamadas, instante)
      cfg = PADROES_ACAO.fetch(afirmacao['tipo'])
      chamada = na_janela(chamadas, cfg[:tool], instante)
      return ['bloquear', 'a ferramenta de ação não rodou'] if chamada.nil?
      return ['bloquear', "a ação voltou #{chamada['status']}: não se sabe se aconteceu"] if
        chamada['status'].to_s != 'ok'

      conferir_conteudo(afirmacao, chamada)
    end

    def conferir_conteudo(afirmacao, chamada)
      texto = chamada['resultado'].to_s
      return ['bloquear', 'o retorno não confirma envio'] unless confirmou_envio?(texto)

      divergencia(afirmacao, texto) || ['permitir', 'a ação confirmou conteúdo compatível']
    end

    # "Mesmo código, mesma quantidade": a ação confirmada tem que ser A MESMA que a fala
    # descreve. Um carrossel de 9 fotos não sustenta um "mandei 12", e fotos do 9412 não
    # sustentam "mandei as do 9849".
    def divergencia(afirmacao, texto)
      codigo = texto[/\b(?:im[óo]vel|c[óo]digo)\s*(\d{3,6})/i, 1]
      return ['bloquear', "a ação foi sobre #{codigo}, a fala diz #{afirmacao['codigo']}"] if
        diferem?(afirmacao['codigo'], codigo)

      quantidade = texto[/\b(\d{1,2})\s*fotos?\b/i, 1]&.to_i
      return ['bloquear', "a ação confirmou #{quantidade}, a fala diz #{afirmacao['quantidade']}"] if
        diferem?(afirmacao['quantidade'], quantidade)

      nil
    end

    # Só divergem quando os DOIS existem. A fala que não declara quantidade não contradiz
    # quantidade nenhuma — "mandei as fotos" continua verdade para um carrossel de 9.
    def diferem?(afirmado, confirmado)
      !afirmado.nil? && !confirmado.nil? && afirmado != confirmado
    end

    def confirmou_envio?(texto)
      texto.match?(/\benvi\w+\b/i) && !texto.match?(/N[ÃA]O envie|n[ãa]o apareceu/i)
    end

    def na_janela(chamadas, tool, instante)
      alvo = Time.zone.parse(instante.to_s)
      Array(chamadas).find do |c|
        c['tool'].to_s == tool && (Time.zone.parse(c['em'].to_s) - alvo).abs <= JANELA_ACAO
      end
    rescue StandardError
      nil
    end

    def normalizar(tipo, bruto)
      return bruto.to_s if tipo == 'codigo'

      numero = bruto.to_s.delete('.').sub(',', '.').to_f
      numero.zero? ? nil : numero
    end
  end
end
