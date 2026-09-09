# frozen_string_literal: true

# A agenda de uma unidade resolvida no BACKEND: o que vale num dia, com feriado, evento e
# temporada já aplicados.
#
# Por que isto passou a existir: a resolução vivia só no front (`units/unitSchedule.js`),
# porque até aqui o único consumidor era a tela. A IA é o segundo consumidor e não tem como
# ler JavaScript — e sem uma fonte no backend ela responde horário de memória, que é como a
# Tozi acumulou 22 endereços de escritório inventados em 90 dias.
#
# A semântica é a MESMA da tela, de propósito: regra de agenda substitui a linha da semana no
# dia em que cai (é assim que ela fecha um feriado e é assim que abre um domingo que a grade
# fecha), a precedência vai da regra mais específica para a mais genérica, e no empate vence a
# que FECHA — nunca prometer ao cliente que a unidade está aberta. Divergir daqui faria a tela
# e a IA responderem coisas diferentes sobre o mesmo dia.
class Units::Agenda
  # Da mais específica para a mais genérica, igual ao `ESPECIFICIDADE` da tela.
  ESPECIFICIDADE = { 'nao_repete' => 0, 'mensal' => 2, 'semanal' => 3, 'anual' => 4 }.freeze
  POSICAO_ULTIMA = -1
  DIA_ULTIMO = -1

  Dia = Data.define(:data, :fechada, :abre, :fecha, :pausa_inicio, :pausa_fim, :motivo) do
    def fechada?
      fechada
    end

    def pausa?
      pausa_inicio.present? && pausa_fim.present?
    end
  end

  def initialize(unit)
    @unit = unit
    @regras = unit.exceptions.to_a
    @grade = unit.working_hours.index_by(&:day_of_week)
  end

  # O que vale neste dia. Devolve nil quando o dia não tem linha na grade E nenhuma regra:
  # dia NÃO CADASTRADO é diferente de dia fechado, e quem lê precisa poder distinguir.
  def dia(data)
    regra = regra_do_dia(data)
    return da_regra(data, regra) if regra

    linha = @grade[data.wday]
    return nil if linha.nil?

    da_grade(data, linha)
  end

  # Grade habitual da semana, sem exceção aplicada — é o que se responde quando ninguém
  # perguntou por um dia específico.
  def semana
    Unit::DIAS_DA_SEMANA.map { |wday| [wday, @grade[wday]] }
  end

  private

  def da_regra(data, regra)
    Dia.new(data: data, fechada: regra.closed_all_day?, motivo: regra.name,
            abre: hhmm(regra.open_hour, regra.open_minutes),
            fecha: hhmm(regra.close_hour, regra.close_minutes),
            pausa_inicio: nil, pausa_fim: nil)
  end

  def da_grade(data, linha)
    Dia.new(data: data, fechada: linha.closed_all_day?, motivo: nil,
            abre: linha.open_all_day? ? '00:00' : hhmm(linha.open_hour, linha.open_minutes),
            fecha: linha.open_all_day? ? '23:59' : hhmm(linha.close_hour, linha.close_minutes),
            pausa_inicio: linha.pausa? ? hhmm(linha.break_start_hour, linha.break_start_minutes) : nil,
            pausa_fim: linha.pausa? ? hhmm(linha.break_end_hour, linha.break_end_minutes) : nil)
  end

  def hhmm(hora, minuto)
    return nil if hora.nil? || minuto.nil?

    format('%<h>02d:%<m>02d', h: hora, m: minuto)
  end

  # Empate na especificidade: vence a que FECHA. É a mesma ordenação da tela.
  def regra_do_dia(data)
    candidatas = @regras.select { |regra| vale_no_dia?(regra, data) }
    return nil if candidatas.empty?

    candidatas.min_by { |regra| [especificidade(regra), regra.closed_all_day? ? 0 : 1] }
  end

  def especificidade(regra)
    return regra.ends_on.present? ? 1 : 0 if regra.frequency == 'nao_repete'

    ESPECIFICIDADE.fetch(regra.frequency, 9)
  end

  def vale_no_dia?(regra, data)
    return false unless dentro_da_janela?(regra, data)

    case regra.frequency
    when 'semanal' then casa_semanal?(regra, data)
    when 'mensal' then casa_mensal?(regra, data)
    when 'anual' then casa_anual?(regra, data)
    else casa_periodo?(regra, data)
    end
  end

  def dentro_da_janela?(regra, data)
    return false if data < regra.starts_on

    regra.until_date.blank? || data <= regra.until_date
  end

  # Regra que não repete pode durar vários dias (`ends_on`): as férias coletivas de 20/12 a
  # 05/01 numa linha só, em vez de dezessete.
  def casa_periodo?(regra, data)
    data <= (regra.ends_on || regra.starts_on)
  end

  def casa_semanal?(regra, data)
    return false unless regra.weekdays.include?(data.wday)

    # Diferença em SEMANAS DE CALENDÁRIO (o `differenceInCalendarWeeks` da tela): a conta é
    # entre os domingos que iniciam cada semana, não entre as datas — senão "a cada 2 semanas"
    # erra sempre que os dois lados caem em posições diferentes da semana.
    semanas = (inicio_da_semana(data) - inicio_da_semana(regra.starts_on)).to_i / 7
    (semanas % regra.repeat_interval).zero?
  end

  # Mensal tem duas formas: pelo dia do mês ("todo dia 10") ou pela posição do dia da semana
  # ("1º e 3º domingo"), que é o que o Google Agenda chama de mensal.
  def casa_mensal?(regra, data)
    meses = ((data.year - regra.starts_on.year) * 12) + (data.month - regra.starts_on.month)
    return false unless (meses % regra.repeat_interval).zero?
    return casa_dia_do_mes?(regra, data) if regra.month_days.present?
    return false unless regra.weekdays.include?(data.wday)

    regra.week_positions.include?(posicao_no_mes(data)) ||
      (regra.week_positions.include?(POSICAO_ULTIMA) && ultima_semana?(data))
  end

  def casa_dia_do_mes?(regra, data)
    regra.month_days.include?(data.day) ||
      (regra.month_days.include?(DIA_ULTIMO) && data.day == data.end_of_month.day)
  end

  def casa_anual?(regra, data)
    ((data.year - regra.starts_on.year) % regra.repeat_interval).zero? &&
      data.month == regra.starts_on.month && data.day == regra.starts_on.day
  end

  def inicio_da_semana(data)
    data - data.wday
  end

  def posicao_no_mes(data)
    ((data.day - 1) / 7) + 1
  end

  def ultima_semana?(data)
    data.day > data.end_of_month.day - 7
  end
end
