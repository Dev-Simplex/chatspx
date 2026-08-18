# Consulta as unidades físicas da conta — contrato em docs/contratos/unidades.md.
#
# ⚠️ O id em config/agents/tools.yml é `buscar_unidades`, mas a CLASSE tem que ser SINGULAR:
# `resolve_tool_class` monta `Captain::Tools::#{id.classify}Tool` e `classify` singulariza, então
# `buscar_unidades` resolve pra `BuscarUnidadeTool`. Classe no plural = tool descartada em
# silêncio no carregamento (é o que acontece hoje com `listar_pecas`, que nunca entra no toolset).
#
# Multi-tenant e opt-in: `active?` nega quando a conta não tem unidade ativa, e aí a tool nem
# entra no toolset do agente. Conta sem unidade cadastrada não muda de comportamento em nada.
class Captain::Tools::BuscarUnidadeTool < Captain::Tools::BasePublicTool
  description 'Consulta as unidades físicas desta empresa: nome, cidade, endereço, telefone e se ' \
              'abre na data que a pessoa pediu, já com feriado e exceção de calendário aplicados. ' \
              'A conta de calendário é feita aqui dentro — repasse a expressão de tempo do jeito ' \
              'que a pessoa escreveu, sem converter em data você mesmo. Use SÓ o que vier no ' \
              'retorno: endereço, telefone e horário que não estiverem aqui não existem.'

  param :cidade, type: 'string',
                 desc: 'O município que a pessoa citou nesta conversa. Vazio lista todas as unidades.',
                 required: false
  param :quando, type: 'string',
                 desc: 'A expressão de tempo exatamente como a pessoa escreveu nesta conversa, sem ' \
                       'converter em data. Vazio quando ela não falou de dia nenhum.',
                 required: false

  LIMITE_UNIDADES = 15
  LIMITE_CIDADES = 25
  MINIMO_CONTINENCIA = 3
  DIAS_ABREVIADOS = %w[dom seg ter qua qui sex sáb].freeze
  DIAS_POR_EXTENSO = %w[Domingo Segunda-feira Terça-feira Quarta-feira
                        Quinta-feira Sexta-feira Sábado].freeze

  SEM_CADASTRO = 'Esta conta não tem unidade cadastrada. Isto não é falha de consulta: não existe ' \
                 'dado de endereço, telefone ou horário de loja pra responder aqui.'.freeze
  FALHA = 'Não consegui consultar as unidades agora. Isto é falha de consulta, não ausência: não ' \
          'conclua que a unidade não existe.'.freeze
  SEM_DATA = 'Nenhuma data foi pedida, então abaixo está o horário habitual. Para um dia específico, ' \
             'chame de novo repassando a expressão de tempo que a pessoa usar.'.freeze

  # Gate multi-tenant. O rescue não é cargo cult: a migration é aplicada com alvo, VM a VM, e sem
  # ele montar o agente numa box ainda não migrada derrubaria o atendimento da frota inteira.
  def active?
    ::Spx::Unidade.ativas.exists?(account_id: @assistant.account_id)
  rescue StandardError => e
    Rails.logger.warn("[BuscarUnidade] active? indisponível: #{e.class} #{e.message}")
    false
  end

  def perform(_tool_context, cidade: nil, quando: nil)
    unidades = unidades_ativas
    return SEM_CADASTRO if unidades.empty?

    encontradas = filtrar_por_cidade(unidades, cidade)
    return sem_unidade_na_cidade(unidades, cidade) if encontradas.empty?

    montar_resposta(encontradas, unidades.size, quando)
  rescue StandardError => e
    Rails.logger.warn("[BuscarUnidade] #{e.class} #{e.message}")
    FALHA
  end

  private

  def unidades_ativas
    ::Spx::Unidade.ativas.where(account_id: @assistant.account_id)
                  .includes(:horarios).order(:cidade, :nome).to_a
  end

  # Compara sem acento e sem caixa, e aceita continência nos dois sentidos porque a pessoa tanto
  # escreve menos que o cadastro quanto escreve mais (a cidade junto com a UF, por exemplo). O piso
  # de tamanho existe pra continência não virar curinga: com uma ou duas letras ela casaria com
  # quase toda cidade, e a lista devolvida deixaria de significar alguma coisa.
  def filtrar_por_cidade(unidades, cidade)
    alvo = ::Spx::Unidade.normalizar(cidade)
    return unidades if alvo.blank?

    exatas = unidades.select { |unidade| ::Spx::Unidade.normalizar(unidade.cidade) == alvo }
    return exatas if exatas.any? || alvo.length < MINIMO_CONTINENCIA

    unidades.select do |unidade|
      nome = ::Spx::Unidade.normalizar(unidade.cidade)
      nome.present? && (nome.include?(alvo) || alvo.include?(nome))
    end
  end

  # A ausência tem que ser inconfundível E dizer o que fazer com ela. Guarda que só devolve um
  # código o agente ignora — foi o que aconteceu quando a IA seguiu qualificando o cliente até o
  # fim e ele descobriu no final que não havia loja.
  def sem_unidade_na_cidade(unidades, cidade)
    cidades = unidades.filter_map { |unidade| unidade.cidade.presence }.uniq
    "Não há unidade cadastrada em \"#{cidade.to_s.strip}\". Isto é resposta confirmada do cadastro, " \
      'não falha de consulta: não invente endereço e não ofereça o de outra cidade como se fosse ' \
      'dessa. Diga à pessoa que não existe unidade nessa cidade ANTES de continuar a conversa. ' \
      "Cidades que têm unidade: #{cidades.first(LIMITE_CIDADES).join(', ')}."
  end

  def montar_resposta(unidades, total_ativas, quando)
    pedido = quando.to_s.strip
    # A expressão é resolvida NO FUSO DE CADA UNIDADE: "amanhã" pode ser dia diferente em cada uma,
    # e resolver uma vez só pelo fuso do servidor é o erro que este desenho existe pra evitar.
    momentos = unidades.index_with { |unidade| ::Spx::UnidadeExpressaoTemporal.resolver(pedido, unidade.zona) }
    excecoes = excecoes_das(momentos.values)
    mostradas = unidades.first(LIMITE_UNIDADES)

    [cabecalho(pedido, momentos.values.first, unidades.size, total_ativas, mostradas.size),
     *mostradas.map { |unidade| bloco(unidade, momentos[unidade], excecoes) }].compact.join("\n\n")
  end

  def excecoes_das(momentos)
    datas = momentos.flat_map(&:datas).uniq
    return [] if datas.empty?

    ::Spx::UnidadeExcecao.where(account_id: @assistant.account_id)
                         .vigentes_entre(datas.min, datas.max).to_a
  end

  # Corte de lista nunca é silencioso: quem lê precisa saber que existe unidade fora do que veio.
  def cabecalho(pedido, momento, encontradas, total_ativas, mostradas)
    corte = mostradas < encontradas
    ["#{encontradas} de #{total_ativas} unidade(s) ativa(s):",
     corte ? "Mostrando #{mostradas} — peça a cidade à pessoa pra reduzir a lista antes de responder." : nil,
     aviso_de_data(pedido, momento)].compact.join(' ')
  end

  # O "não entendi a data" é obrigatório e é o oposto de cair em hoje por omissão.
  def aviso_de_data(pedido, momento)
    return SEM_DATA if pedido.blank?
    return nil if momento.reconhecida?

    "Não consegui transformar \"#{pedido}\" em data. NÃO trate como hoje e não responda por data " \
      'nenhuma: pergunte à pessoa qual é o dia e chame esta ferramenta de novo. O horário habitual ' \
      'abaixo vale pra semana comum e pode ter exceção justamente no dia que ela quer.'
  end

  def bloco(unidade, momento, excecoes)
    linhas = ["#{unidade.nome}#{local(unidade)}"]
    linhas << "Endereço: #{unidade.endereco}" if unidade.endereco.present?
    linhas << "Telefone: #{unidade.telefone}" if unidade.telefone.present?
    linhas.concat(atributos(unidade))
    linhas.concat(agenda(unidade, momento, excecoes))
    linhas.join("\n")
  end

  def local(unidade)
    partes = [unidade.cidade.presence, unidade.uf.presence].compact
    partes.any? ? " — #{partes.join('/')}" : ''
  end

  def atributos(unidade)
    (unidade.atributos || {}).filter_map do |chave, valor|
      texto = valor.is_a?(Array) ? valor.join(', ') : valor.to_s
      "#{chave.to_s.humanize}: #{texto}" if texto.present?
    end
  end

  def agenda(unidade, momento, excecoes)
    return ["Horário: #{horario_habitual(unidade)}"] unless momento.reconhecida?

    linhas = momento.datas.map { |data| linha_do_dia(unidade, data, excecoes) }
    linhas << linha_de_agora(unidade, momento, excecoes) if momento.instante?
    linhas
  end

  def linha_do_dia(unidade, data, excecoes)
    estado = unidade.estado_em(data, escopo_excecoes: excecoes)
    "#{DIAS_POR_EXTENSO[data.wday]}, #{data.strftime('%d/%m/%Y')}: #{situacao(unidade, estado)}"
  end

  def linha_de_agora(unidade, momento, excecoes)
    instante = momento.instante
    estado = unidade.estado_em(instante.to_date, escopo_excecoes: excecoes)
    relogio = "Agora (#{instante.strftime('%H:%M')} no fuso da unidade)"
    return "#{relogio}: horário não cadastrado, não dá pra dizer." unless sabe_o_horario?(unidade, estado)

    aberta = estado.aberta_em?((instante.hour * 60) + instante.min)
    "#{relogio}: #{aberta ? 'aberta' : 'fechada'}."
  end

  def situacao(unidade, estado)
    return 'horário não cadastrado — não afirme que abre nem que fecha.' unless sabe_o_horario?(unidade, estado)

    base = estado.aberta? ? "aberta das #{estado.faixas.map(&:to_s).join(' e das ')}" : 'fechada'
    "#{base}#{ressalva(estado)}"
  end

  # Grade não cadastrada NÃO é loja fechada. Responder "fechada" aqui seria inventar um dado que
  # ninguém cadastrou — e invenção com formato de dado chega ao cliente como verdade.
  def sabe_o_horario?(unidade, estado)
    unidade.horario_cadastrado? || estado.por_excecao?
  end

  def ressalva(estado)
    return '' unless estado.por_excecao?
    return " (exceção nesta data: #{estado.motivo})" if estado.motivo.present?

    ' (horário excepcional nesta data)'
  end

  # Semana condensada em faixas de dias iguais: a grade dia a dia é longa, e o que o agente
  # precisa é do padrão, não de sete linhas quase idênticas.
  def horario_habitual(unidade)
    return 'não cadastrado.' unless unidade.horario_cadastrado?

    agrupar_semana(unidade).map { |grupo| "#{rotulo_dias(grupo[:dias])} #{grupo[:texto]}" }.join(' · ')
  end

  def agrupar_semana(unidade)
    ::Spx::Unidade::ORDEM_LEITURA.each_with_object([]) do |wday, acc|
      texto = unidade.faixas_padrao(wday).map(&:to_s).join(' e ').presence || 'fechada'
      if acc.last && acc.last[:texto] == texto
        acc.last[:dias] << wday
      else
        acc << { dias: [wday], texto: texto }
      end
    end
  end

  def rotulo_dias(dias)
    return DIAS_ABREVIADOS[dias.first] if dias.one?

    "#{DIAS_ABREVIADOS[dias.first]} a #{DIAS_ABREVIADOS[dias.last]}"
  end
end
