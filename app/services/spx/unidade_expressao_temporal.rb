# Transforma a expressão de tempo COMO A PESSOA ESCREVEU em datas absolutas, no fuso da unidade.
#
# Isto é o ponto do desenho, não um detalhe: no n8n a instrução era o MODELO converter "abre
# amanhã?" em data antes de consultar. É exatamente onde ele erra, e erra com convicção. Aqui a
# conta é aritmética de calendário em Ruby, e a IA recebe pronto.
#
# COROLÁRIO QUE VALE MAIS QUE O RESTO: quando a expressão não for resolvível, o resultado diz
# isso. NUNCA cai em "hoje" por omissão — silêncio que vira palpite é o tipo de falha que esta
# base já pagou caro mais de uma vez.
class Spx::UnidadeExpressaoTemporal
  # `datas` vazio com `reconhecida` false é a ausência explícita; quem chama tem que tratar.
  # `instante` só vem preenchido quando a pergunta é sobre o momento presente ("está aberto
  # agora"), porque aí a resposta é hora contra faixa, não só dia.
  Resultado = Data.define(:datas, :instante, :reconhecida) do
    def reconhecida?
      reconhecida
    end

    def instante?
      instante.present?
    end
  end

  DIAS_SEMANA = { 'domingo' => 0, 'segunda' => 1, 'terca' => 2, 'quarta' => 3,
                  'quinta' => 4, 'sexta' => 5, 'sabado' => 6 }.freeze

  MESES = { 'janeiro' => 1, 'fevereiro' => 2, 'marco' => 3, 'abril' => 4, 'maio' => 5, 'junho' => 6,
            'julho' => 7, 'agosto' => 8, 'setembro' => 9, 'outubro' => 10, 'novembro' => 11,
            'dezembro' => 12 }.freeze

  MOMENTO_PRESENTE = /\bagora\b|\b(neste|nesse)\s+momento\b/
  FIM_DE_SEMANA = /\b(fim|final)\s+de\s+semana\b/
  DATA_NUMERICA = %r{\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b}
  DIA_DO_MES = /\bdia\s+(\d{1,2})\b/
  DATA_POR_EXTENSO = /\b(\d{1,2})\s+de\s+([a-z]+)\b/
  QUALIFICADOR_SEGUINTE = /\bque\s+vem\b|\bproximo\b|\bproxima\b/

  def self.resolver(expressao, zona)
    new(expressao, zona).resolver
  end

  def initialize(expressao, zona)
    @texto = self.class.normalizar(expressao)
    @agora = Time.current.in_time_zone(zona)
    @hoje = @agora.to_date
  end

  def self.normalizar(expressao)
    ActiveSupport::Inflector.transliterate(expressao.to_s).downcase.gsub(/\s+/, ' ').strip
  end

  def resolver
    return nao_reconhecida if @texto.blank?

    datas = datas_resolvidas
    return nao_reconhecida if datas.blank?

    Resultado.new(datas: datas.uniq.sort.first(7), instante: momento_presente? ? @agora : nil, reconhecida: true)
  end

  private

  # A ordem importa: "depois de amanhã" contém "amanhã", e "dia 25/12" contém "dia 25".
  def datas_resolvidas
    datas_relativas || datas_fim_de_semana || datas_numericas ||
      datas_por_extenso || datas_dia_do_mes || datas_por_dia_semana
  end

  def datas_relativas
    return [@hoje + 2] if @texto.include?('depois de amanha')
    return [@hoje + 1] if @texto.match?(/\bamanha\b/)
    return [@hoje - 1] if @texto.match?(/\bontem\b/)
    return [@hoje] if @texto.match?(/\bhoje\b/) || momento_presente?

    nil
  end

  # Devolver só o sábado seria escolher por conta própria qual dos dois dias a pessoa quis —
  # o mesmo palpite silencioso que o contrato proíbe. Num domingo, o fim de semana em curso
  # é o próprio dia: o sábado já passou e ninguém pergunta horário de um dia que passou.
  def datas_fim_de_semana
    return nil unless @texto.match?(FIM_DE_SEMANA)
    return [@hoje] if @hoje.wday.zero?

    sabado = @hoje + ((6 - @hoje.wday) % 7)
    [sabado, sabado + 1]
  end

  def datas_numericas
    encontrado = @texto.match(DATA_NUMERICA)
    return nil unless encontrado

    dia = encontrado[1].to_i
    mes = encontrado[2].to_i
    return uma(data_valida(ano_de(encontrado[3]), mes, dia)) if encontrado[3].present?

    uma(proxima_ocorrencia_anual(mes, dia))
  end

  def datas_por_extenso
    encontrado = @texto.match(DATA_POR_EXTENSO)
    mes = encontrado && MESES[encontrado[2]]
    return nil unless mes

    uma(proxima_ocorrencia_anual(mes, encontrado[1].to_i))
  end

  def datas_dia_do_mes
    encontrado = @texto.match(DIA_DO_MES)
    return nil unless encontrado

    uma(proxima_ocorrencia_mensal(encontrado[1].to_i))
  end

  # Data inválida (31 de fevereiro) devolve nil, e nil aqui tem que virar "não reconheci" —
  # não pode virar lista vazia que o chamador leia como "resolvi e não tem nada".
  def uma(data)
    data ? [data] : nil
  end

  # Varre TODOS os dias da semana citados: quem pergunta por dois dias está perguntando pelos
  # dois, e devolver um só é escolher por ela. A posição no texto só serve pra tornar o mapeamento
  # determinístico (o resultado final sai em ordem de calendário).
  def datas_por_dia_semana
    citados = DIAS_SEMANA.filter_map do |nome, wday|
      posicao = @texto =~ /\b#{Regexp.escape(nome)}\b/
      [posicao, wday] if posicao
    end
    return nil if citados.empty?

    citados.sort_by(&:first).map { |(_posicao, wday)| proxima_data_da_semana(wday) }
  end

  # Sem qualificador, a próxima ocorrência INCLUI hoje: quem pergunta "abre sábado" num sábado
  # está falando do dia em que está. Com "que vem"/"próximo", pula pra semana seguinte.
  def proxima_data_da_semana(wday)
    data = @hoje + ((wday - @hoje.wday) % 7)
    data += 7 if data == @hoje && @texto.match?(QUALIFICADOR_SEGUINTE)
    data
  end

  # Sem ano, escolhe a ocorrência que ainda não passou. Ancorar no ano corrente resolveria
  # "2 de janeiro", perguntado em dezembro, pra uma data no passado — errado com convicção.
  def proxima_ocorrencia_anual(mes, dia)
    candidata = data_valida(@hoje.year, mes, dia)
    return candidata if candidata && candidata >= @hoje

    data_valida(@hoje.year + 1, mes, dia)
  end

  def proxima_ocorrencia_mensal(dia)
    candidata = data_valida(@hoje.year, @hoje.month, dia)
    return candidata if candidata && candidata >= @hoje

    seguinte = @hoje.next_month
    data_valida(seguinte.year, seguinte.month, dia)
  end

  def ano_de(texto)
    ano = texto.to_i
    ano < 100 ? 2000 + ano : ano
  end

  def data_valida(ano, mes, dia)
    Date.new(ano, mes, dia)
  rescue Date::Error
    nil
  end

  def momento_presente?
    @texto.match?(MOMENTO_PRESENTE)
  end

  def nao_reconhecida
    Resultado.new(datas: [], instante: nil, reconhecida: false)
  end
end
