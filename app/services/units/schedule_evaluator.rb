# frozen_string_literal: true

# Avalia a agenda de uma unidade no backend: qual regra manda num dia e se ela fecha
# a unidade agora, no fuso da própria unidade.
#
# Esta é a PORTA em Ruby de `units/unitSchedule.js`. A duplicação é deliberada: a tela
# precisa responder "aberta agora" a cada 60 s sem ir à rede, e o backend precisa da
# mesma resposta para fechar a caixa de entrada no feriado. Para as duas não
# divergirem, os casos moram em `spec/fixtures/units/schedule_cases.json` e alimentam
# o spec dos dois lados — regra nova entra no fixture primeiro.
class Units::ScheduleEvaluator
  # Da mais específica para a mais genérica — mesma ordem escrita na tela.
  ESPECIFICIDADE = { 'nao_repete' => 0, 'mensal' => 2, 'semanal' => 3, 'anual' => 4 }.freeze

  # --- avaliação de uma regra isolada (o que o fixture cobre) ------------------------

  # A regra cai neste dia?
  def self.rule_on?(rule, date)
    date = date.to_date
    return false if date < rule.starts_on
    return false if rule.until_date.present? && date > rule.until_date

    case rule.frequency
    when 'semanal' then weekly?(rule, date)
    when 'mensal' then monthly?(rule, date)
    when 'anual' then yearly?(rule, date)
    else period?(rule, date)
    end
  end

  # Período (`ends_on`) é a duração de uma regra que NÃO repete: as férias coletivas de
  # 20/12 a 05/01 numa linha só, em vez de dezessete.
  def self.period?(rule, date)
    date <= (rule.ends_on || rule.starts_on)
  end

  def self.weekly?(rule, date)
    return false unless rule.weekdays.include?(date.wday)

    (semanas_de_calendario(rule.starts_on, date) % rule.repeat_interval).zero?
  end

  # Mensal tem duas formas: pelo dia do mês ("todo dia 10") ou pela posição do dia da
  # semana ("1º e 3º domingo") — é esta segunda que o Google Agenda chama de mensal.
  def self.monthly?(rule, date)
    return false unless (meses_de_calendario(rule.starts_on, date) % rule.repeat_interval).zero?
    return por_dia_do_mes?(rule, date) if rule.month_days.any?

    por_posicao_no_mes?(rule, date)
  end

  def self.por_dia_do_mes?(rule, date)
    rule.month_days.include?(date.day) ||
      (rule.month_days.include?(-1) && date.day == date.end_of_month.day)
  end

  def self.por_posicao_no_mes?(rule, date)
    return false unless rule.weekdays.include?(date.wday)

    rule.week_positions.include?(posicao_no_mes(date)) ||
      (rule.week_positions.include?(-1) && ultima_semana?(date))
  end

  def self.yearly?(rule, date)
    ((date.year - rule.starts_on.year) % rule.repeat_interval).zero? &&
      date.month == rule.starts_on.month &&
      date.day == rule.starts_on.day
  end

  # date-fns conta SEMANAS DE CALENDÁRIO começando no domingo, não períodos de 7 dias:
  # de sábado para domingo já é uma semana. Contar por (date - starts_on) / 7 daria
  # outro resultado e a regra "a cada 2 semanas" cairia no dia errado.
  def self.semanas_de_calendario(inicio, date)
    ((domingo_da_semana(date) - domingo_da_semana(inicio)).to_i / 7)
  end

  def self.domingo_da_semana(date)
    date - date.wday
  end

  def self.meses_de_calendario(inicio, date)
    ((date.year * 12) + date.month) - ((inicio.year * 12) + inicio.month)
  end

  def self.posicao_no_mes(date)
    (date.day / 7.0).ceil
  end

  def self.ultima_semana?(date)
    date.day > date.end_of_month.day - 7
  end

  private_class_method :period?, :weekly?, :monthly?, :yearly?, :por_dia_do_mes?, :por_posicao_no_mes?,
                       :semanas_de_calendario, :domingo_da_semana, :meses_de_calendario,
                       :posicao_no_mes, :ultima_semana?

  # --- a unidade -------------------------------------------------------------------

  def initialize(unit)
    @unit = unit
  end

  # Qual regra manda no dia. Empate na especificidade: vence a que FECHA — nunca
  # prometer ao cliente que a filial está aberta.
  def rule_on(date)
    candidatas = @unit.exceptions.select { |regra| self.class.rule_on?(regra, date) }
    return nil if candidatas.empty?

    candidatas.min_by { |regra| [especificidade(regra), regra.closed_all_day? ? 0 : 1] }
  end

  def today
    Time.current.in_time_zone(@unit.timezone).to_date
  end

  # A unidade está fechada AGORA por causa de uma regra de agenda?
  #   nil   -> nenhuma regra hoje; quem decide é quem perguntou (o horário da caixa)
  #   true  -> fechada (dia inteiro, ou fora da faixa que a regra abriu)
  #   false -> aberta pela regra
  def closed_by_rule_now?(reference = Time.current)
    agora = reference.in_time_zone(@unit.timezone)
    regra = rule_on(agora.to_date)
    return nil if regra.nil?
    return true if regra.closed_all_day?

    minutos = (agora.hour * 60) + agora.min
    minutos < minutos_de(regra.open_hour, regra.open_minutes) ||
      minutos >= minutos_de(regra.close_hour, regra.close_minutes)
  end

  private

  def especificidade(regra)
    return regra.ends_on.present? ? 1 : 0 if regra.nao_repete?

    ESPECIFICIDADE.fetch(regra.frequency, 9)
  end

  def minutos_de(hora, minuto)
    (hora.to_i * 60) + minuto.to_i
  end
end
