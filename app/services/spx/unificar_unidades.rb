# Copia o cadastro da tabela `unidades` (aposentada) para `units`, que passou a ser a unica.
#
# SQL cru de proposito: os modelos do lado antigo saem neste mesmo PR, e um servico que dependa
# deles morre junto. Assim ele continua rodando depois — inclusive numa VM que ficou para tras.
#
# `puts` de proposito: isto e um relator de rake, e a saida E o produto — quem roda precisa ver
# unidade a unidade o que sera gravado antes de deixar gravar.
# rubocop:disable Rails/Output
class Spx::UnificarUnidades
  def initialize(executar:)
    @executar = executar
    @avisos = []
  end

  def call
    puts @executar ? '== GRAVANDO ==' : '== SECO (nada sera gravado) =='
    linhas = sql('SELECT * FROM unidades ORDER BY id')
    puts "  unidades na origem: #{linhas.size}"
    linhas.each { |linha| migrar(linha) }
    puts @avisos.empty? ? '  sem avisos' : "  AVISOS (#{@avisos.size}):"
    @avisos.each { |a| Rails.logger.debug "    - #{a}" }
  end

  private

  def sql(query, *binds)
    ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([query, *binds])).to_a
  end

  def migrar(origem)
    existente = sql('SELECT id, name FROM units WHERE account_id = ? AND lower(name) = lower(?)', origem['account_id'], origem['nome']).first
    if existente
      @avisos << "unidade ##{origem['id']} #{origem['nome'].inspect}: ja existe units ##{existente['id']} com esse nome — nao sobrescrevi"
      return
    end

    puts "  unidade ##{origem['id']} #{origem['nome'].inspect} (#{origem['cidade']}/#{origem['uf']})"
    unit_id = criar_unit(origem)
    horarios(origem, unit_id)
    excecoes(origem, unit_id)
  end

  def criar_unit(origem)
    return nil unless @executar

    unit = Unit.new(account_id: origem['account_id'], name: origem['nome'], city: origem['cidade'], state: origem['uf'],
                    address: origem['endereco'], phone: origem['telefone'], timezone: origem['timezone'].presence || 'America/Cuiaba',
                    active: origem['ativa'], latitude: origem['latitude'], longitude: origem['longitude'],
                    etiquetas: jsonb(origem['etiquetas'], []), atributos: jsonb(origem['atributos'], {}))
    # A grade padrao do callback atrapalha: a de verdade vem da origem, logo abaixo.
    unit.save!
    unit.working_hours.destroy_all
    puts "    -> units ##{unit.id}"
    unit.id
  end

  def horarios(origem, unit_id)
    # `to_char` no SQL: sem ele o driver devolve a coluna `time` e a conversao vira adivinhacao.
    # Aqui o que chega e o relogio gravado, em texto, e o `hm` faz a unica conversao que existe.
    linhas = sql("SELECT dia_semana, fechada, to_char(abre, 'HH24:MI') AS abre, " \
                 "to_char(fecha, 'HH24:MI') AS fecha " \
                 'FROM unidade_horarios WHERE unidade_id = ? ORDER BY dia_semana, abre', origem['id'])
    linhas.group_by { |h| h['dia_semana'] }.sort.each do |dia, do_dia|
      if do_dia.size > 2
        @avisos << "unidade ##{origem['id']} dia #{dia}: #{do_dia.size} faixas — a tabela nova cabe em 2 " \
                   '(abre/fecha + intervalo). Nao converti este dia.'
        next
      end
      atributos = grade(dia, do_dia)
      puts "    dia #{dia}: #{descrever(atributos)}"
      UnitWorkingHour.create!(atributos.merge(unit_id: unit_id)) if @executar
    end
  end

  def grade(dia, do_dia)
    return { day_of_week: dia, closed_all_day: true } if do_dia.all? { |h| h['fechada'] }

    abertos = do_dia.reject { |h| h['fechada'] }
    base = { day_of_week: dia, closed_all_day: false }.merge(hm(:open, abertos.first['abre']), hm(:close, abertos.last['fecha']))
    return base if abertos.size == 1

    # Duas faixas: o vao entre o fim da primeira e o inicio da segunda E o intervalo.
    base.merge(hm(:break_start, abertos.first['fecha']), hm(:break_end, abertos.last['abre']))
  end

  # A coluna `time` da tabela antiga guarda em UTC, e o Rails convertia para `Time.zone` na
  # leitura: 11:30 gravado e 07:30 na tela, que e o horario que o cliente ve e a IA responde.
  # `unit_working_hours` guarda hora de PAREDE em inteiro — sem converter aqui, a unidade
  # abriria 4 horas mais tarde. Medido na Tozi: o ensaio seco propunha 11:30-21:30 para uma
  # loja que abre 07:30-17:30.
  #
  # `Time.zone` e nao o fuso da unidade de proposito: e ele que produziu o 07:30 que existe
  # hoje, e reproduzir a leitura antiga vale mais que corrigi-la no meio de uma copia.
  def hm(prefixo, valor)
    hora, minuto = valor.to_s.split(':').first(2).map(&:to_i)
    return {} if valor.blank?

    local = Time.utc(2000, 1, 1, hora, minuto).in_time_zone(Time.zone)
    { :"#{prefixo}_hour" => local.hour, :"#{prefixo}_minutes" => local.min }
  end

  def hhmm(hora, minuto)
    format('%<h>02d:%<m>02d', h: hora.to_i, m: minuto.to_i)
  end

  def descrever(grade)
    return 'fechada' if grade[:closed_all_day]

    janela = "#{hhmm(grade[:open_hour], grade[:open_minutes])}-#{hhmm(grade[:close_hour], grade[:close_minutes])}"
    return janela if grade[:break_start_hour].nil?

    pausa = "#{hhmm(grade[:break_start_hour], grade[:break_start_minutes])}-#{hhmm(grade[:break_end_hour], grade[:break_end_minutes])}"
    "#{janela} (intervalo #{pausa})"
  end

  def excecoes(origem, unit_id)
    sql('SELECT motivo, etiqueta, data_inicio, data_fim, fechada, ' \
        "to_char(abre, 'HH24:MI') AS abre, to_char(fecha, 'HH24:MI') AS fecha " \
        'FROM unidade_excecoes WHERE unidade_id = ?', origem['id']).each do |e|
      nome = e['motivo'].presence || e['etiqueta'].presence || 'Exceção'
      puts "    excecao #{nome.inspect} #{e['data_inicio']}..#{e['data_fim']}"
      next unless @executar

      UnitException.create!({ unit_id: unit_id, name: nome, starts_on: e['data_inicio'], ends_on: e['data_fim'],
                              closed_all_day: e['fechada'], category: :feriado, frequency: :nao_repete }
                              .merge(hm(:open, e['abre']), hm(:close, e['fecha'])))
    end
    avisar_excecoes_por_etiqueta(origem['account_id'])
  end

  # A tabela antiga permitia regra sem unidade, valendo para toda unidade marcada com a etiqueta.
  # `unit_exceptions` e sempre de UMA unidade — essas nao tem para onde ir, e a task diz quantas.
  def avisar_excecoes_por_etiqueta(account_id)
    orfas = sql('SELECT COUNT(*) AS n FROM unidade_excecoes WHERE unidade_id IS NULL AND account_id = ?', account_id)
            .first['n'].to_i
    return unless orfas.positive?

    @avisos << "conta #{account_id}: #{orfas} excecao(oes) por ETIQUETA — a tabela nova e sempre de uma unidade. Nao converti."
  end

  def jsonb(valor, padrao)
    return padrao if valor.blank?

    valor.is_a?(String) ? JSON.parse(valor) : valor
  rescue JSON::ParserError
    padrao
  end
end
# rubocop:enable Rails/Output
