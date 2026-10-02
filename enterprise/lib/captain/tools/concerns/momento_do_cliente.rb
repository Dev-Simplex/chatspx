# Lê o momento que o CLIENTE disse ("às 21h30", "quinta de manhã", "semana que vem") e o converte
# em minutos a partir de agora. Compartilhado pela programar_followup (cutucada com `janela`) e
# pela agendar_mensagem (agendada), para que as duas leiam a fala do cliente do mesmo jeito.
module Captain::Tools::MomentoDoCliente
  DIAS_SEMANA = { 'domingo' => 0, 'segunda' => 1, 'terca' => 2, 'quarta' => 3,
                  'quinta' => 4, 'sexta' => 5, 'sabado' => 6 }.freeze
  # Hora de referência de cada período do dia.
  PERIODOS = { 'manha' => 9, 'almoco' => 12, 'tarde' => 14, 'noite' => 19 }.freeze

  private

  # Converte a janela declarada pelo cliente em minutos a partir de agora.
  # nil quando o texto não traz dia nem hora reconhecíveis — aí quem manda é `minutos`.
  def minutos_ate(janela)
    texto = sem_acento(janela)
    dia = data_alvo(texto)
    relogio = hora_alvo(texto)
    return nil if dia.nil? && relogio.nil?

    hora, minuto = relogio || [PERIODOS['manha'], 0]
    momento = momento_de(dia || Time.current.to_date, hora, minuto)
    ((momento - Time.current) / 60).round
  end

  # Janela já vencida hoje (pediu "de manhã" à tarde) cai no dia seguinte.
  def momento_de(dia, hora, minuto = 0)
    momento = Time.zone.local(dia.year, dia.month, dia.day, hora, minuto)
    momento <= Time.current ? momento + 1.day : momento
  end

  def data_alvo(texto)
    hoje = Time.current.to_date
    return hoje if texto.match?(/\bhoje\b|agora a (tarde|noite)|mais tarde/)
    return hoje + 2 if texto.include?('depois de amanha')
    return hoje + 1 if texto.match?(/\bamanha\b/)
    # "semana que vem" caía no nil e, sem hora junto, a janela inteira era descartada: o cliente
    # pedia uma semana e levava a cutucada que o modelo tinha escolhido — minutos depois.
    return hoje + 7 if texto.match?(/(semana|mes) que vem|proxima semana/)

    dia_da_semana(texto, hoje)
  end

  def dia_da_semana(texto, hoje)
    nome, alvo = DIAS_SEMANA.find { |n, _| texto.include?(n) }
    return nil if nome.nil?

    delta = (alvo - hoje.wday) % 7
    hoje + (delta.zero? ? 7 : delta)
  end

  # Devolve [hora, minuto] ou nil.
  #
  # O padrão antigo terminava em \b e por isso NÃO casava "21h30" — a forma mais comum de dizer
  # hora quebrada em português. Entre o "h" e o "3" não há fronteira de palavra, então a janela
  # virava nil e o horário que o cliente pediu era descartado em silêncio.
  def hora_alvo(texto)
    casou = texto.match(/\b(\d{1,2})\s*(?:h(?:oras?)?|:)\s*(\d{2})?/)
    if casou
      hora = casou[1].to_i
      minuto = casou[2].to_i
      return [hora, minuto] if hora.between?(0, 23) && minuto.between?(0, 59)
    end

    # Fronteira de palavra é obrigatória: "amanha" CONTÉM "manha", e sem \b
    # "amanhã à tarde" era agendado de manhã.
    _, hora = PERIODOS.find { |p, _| texto.match?(/\b#{p}\b/) }
    hora && [hora, 0]
  end

  def sem_acento(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
  end
end
