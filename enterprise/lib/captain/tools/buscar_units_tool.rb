# Consulta as unidades da conta (módulo `units`): endereço, telefone e horário, com feriado e
# exceção de calendário já resolvidos.
#
# Existe porque a IA precisa de uma FONTE para esses fatos. Sem ela, endereço e horário saem da
# memória do modelo — medido na Tozi em 90 dias: das 49 vezes em que a IA deu o endereço do
# escritório, 22 estavam erradas, e nunca a mesma rua.
#
# Multi-tenant e opt-in por DADO: `active?` nega quando a conta não tem unidade ativa, e aí a
# tool nem entra no toolset. Conta sem unidade cadastrada não muda de comportamento em nada.
class Captain::Tools::BuscarUnitsTool < Captain::Tools::BasePublicTool
  description 'Consulta as unidades desta empresa: nome, cidade, endereço, telefone e se abre ' \
              'na data que a pessoa pediu, já com feriado e exceção de calendário aplicados. ' \
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
  DIAS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  ABREVIADOS = %w[dom seg ter qua qui sex sáb].freeze

  SEM_CADASTRO = 'Esta conta não tem unidade cadastrada. Isto não é falha de consulta: não existe ' \
                 'dado de endereço, telefone ou horário para responder aqui.'.freeze
  FALHA = 'Não consegui consultar as unidades agora. Isto é falha de consulta, não ausência: não ' \
          'conclua que a unidade não existe.'.freeze
  SEM_DATA = 'Nenhuma data foi pedida, então abaixo está o horário habitual. Para um dia específico, ' \
             'chame de novo repassando a expressão de tempo que a pessoa usar.'.freeze

  # Gate multi-tenant. O rescue não é zelo: a migration é aplicada VM a VM, e montar o agente
  # numa box ainda não migrada derrubaria o atendimento da frota inteira.
  def active?
    ::Unit.exists?(account_id: @assistant.account_id, active: true)
  rescue StandardError => e
    Rails.logger.warn("[BuscarUnits] active? indisponível: #{e.class} #{e.message}")
    false
  end

  def perform(_tool_context, cidade: nil, quando: nil)
    unidades = ::Unit.where(account_id: @assistant.account_id, active: true)
                     .includes(:working_hours, :exceptions).limit(LIMITE_UNIDADES).to_a
    return SEM_CADASTRO if unidades.empty?

    encontradas = filtrar_por_cidade(unidades, cidade)
    return sem_unidade_na_cidade(unidades, cidade) if encontradas.empty?

    montar(encontradas, unidades.size, quando)
  rescue StandardError => e
    Rails.logger.warn("[BuscarUnitsTool] #{e.class}: #{e.message}")
    FALHA
  end

  private

  def filtrar_por_cidade(unidades, cidade)
    return unidades if cidade.blank?

    alvo = normalizar(cidade)
    achadas = unidades.select { |u| normalizar(u.city).include?(alvo) || alvo.include?(normalizar(u.city)) }
    achadas.presence || []
  end

  def normalizar(texto)
    I18n.transliterate(texto.to_s).downcase.strip
  end

  # "Não temos unidade nessa cidade" é resposta diferente de "não temos unidade nenhuma", e a
  # segunda seria mentira. Diz o que existe, para a IA poder oferecer.
  def sem_unidade_na_cidade(unidades, cidade)
    cidades = unidades.filter_map(&:city).uniq.join(', ')
    "Nenhuma unidade em #{cidade}. As cidades onde existe unidade são: #{cidades}. " \
      'Diga isso como fato consultado e ofereça a mais conveniente — não conclua que a empresa não atende a região.'
  end

  def montar(unidades, total, quando)
    cabecalho = "#{unidades.size} de #{total} unidade(s) ativa(s):"
    datas = resolver_datas(unidades.first, quando)
    cabecalho = "#{cabecalho} #{SEM_DATA}" if quando.present? && datas.blank?
    cabecalho = "#{cabecalho} #{SEM_DATA}" if quando.blank?
    ([cabecalho] + unidades.map { |u| bloco(u, datas) }).join("\n\n")
  end

  # A conta de calendário é aritmética em Ruby, não palpite do modelo — e quando a expressão
  # não é resolvível, o resultado diz isso em vez de cair em "hoje" por omissão.
  def resolver_datas(unidade, quando)
    return [] if quando.blank?

    resultado = ::Spx::UnidadeExpressaoTemporal.resolver(quando, unidade.timezone)
    resultado.reconhecida? ? resultado.datas : []
  rescue StandardError => e
    Rails.logger.warn("[BuscarUnitsTool] expressão '#{quando}': #{e.class}")
    []
  end

  def bloco(unidade, datas)
    linhas = ["#{unidade.name} — #{[unidade.city, unidade.state].compact_blank.join('/')}"]
    linhas << "Endereço: #{unidade.address}" if unidade.address.present?
    linhas << "Telefone: #{unidade.phone}" if unidade.phone.present?
    linhas << "Observações: #{unidade.notes}" if unidade.notes.present?
    linhas << (datas.present? ? nos_dias(unidade, datas) : horario_habitual(unidade))
    linhas.join("\n")
  end

  def nos_dias(unidade, datas)
    agenda = ::Units::Agenda.new(unidade)
    datas.map do |data|
      dia = agenda.dia(data)
      rotulo = "#{DIAS[data.wday].capitalize}, #{data.strftime('%d/%m/%Y')}"
      next "#{rotulo}: dia sem horário cadastrado — não afirme que abre nem que fecha." if dia.nil?

      "#{rotulo}: #{descrever(dia)}"
    end.join("\n")
  end

  def descrever(dia)
    return "fechada#{motivo(dia)}" if dia.fechada?

    faixa = if dia.pausa?
              "das #{dia.abre} às #{dia.pausa_inicio} e das #{dia.pausa_fim} às #{dia.fecha}"
            else
              "das #{dia.abre} às #{dia.fecha}"
            end
    "aberta #{faixa}#{motivo(dia)}"
  end

  def motivo(dia)
    dia.motivo.present? ? " (#{dia.motivo})" : ''
  end

  # Dia sem linha some da lista: linha ausente é dia NÃO cadastrado, e listá-lo como fechado
  # afirmaria o que ninguém cadastrou.
  def horario_habitual(unidade)
    agenda = ::Units::Agenda.new(unidade)
    partes = agenda.semana.filter_map do |wday, linha|
      next if linha.nil?

      dia = agenda.send(:da_grade, Time.zone.today, linha)
      next "#{ABREVIADOS[wday]} fechada" if dia.fechada?

      "#{ABREVIADOS[wday]} #{dia.abre} às #{dia.fecha}#{dia.pausa? ? " (pausa #{dia.pausa_inicio}–#{dia.pausa_fim})" : ''}"
    end
    return 'Horário não cadastrado.' if partes.empty?

    "Horário: #{partes.join(' · ')}"
  end
end
