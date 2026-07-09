# frozen_string_literal: true

# Empurra um instante FUTURO (o `wait_until` calculado pelo Flows::RunnerService) para a
# próxima abertura comercial da inbox, quando o nó `wait` pede `business_hours: true`. Usa os
# campos REAIS do WorkingHour (day_of_week, open_hour/open_minutes, close_hour/close_minutes,
# closed_all_day) no timezone da inbox — o mesmo material que Inbox#out_of_office?/working_now?
# consomem, mas projetado para um instante futuro (working_now? só enxerga o AGORA, então não
# serve para decidir sobre um wait que vence daqui a horas/dias).
#
# Gate igual ao do Inbox#out_of_office?: sem `working_hours_enabled?` o expediente não está
# configurado e devolvemos o `from` intacto (no-op). Se o instante já cai DENTRO do expediente,
# também é no-op. Caso contrário, devolve o open_hour:open_minutes do próximo dia não
# `closed_all_day` após o `from`.
class Flows::BusinessHours
  # Dias varridos a partir do `from`: o próprio dia do `from` (parcial — só o trecho após o
  # horário) + uma semana inteira, o que garante achar qualquer dia aberto do WorkingHour
  # semanal (7 linhas, uma por day_of_week).
  SCAN_DAYS = (0..7)

  def self.next_opening(inbox, from:)
    new(inbox, from).next_opening
  end

  def initialize(inbox, from)
    @inbox = inbox
    @from = from
  end

  def next_opening
    return @from unless configured?

    from_local = @from.in_time_zone(timezone)
    SCAN_DAYS.each do |offset|
      day = from_local + offset.days
      working_hour = schedule[day.wday]
      next if working_hour.nil? || working_hour.closed_all_day?

      opening = day.change(hour: working_hour.open_hour, min: working_hour.open_minutes, sec: 0)
      closing = day.change(hour: working_hour.close_hour, min: working_hour.close_minutes, sec: 0)

      pushed = resolve(offset, from_local, opening, closing)
      return pushed if pushed
    end

    @from # inbox com expediente ligado mas sem nenhum dia aberto na semana — no-op defensivo
  end

  private

  # No dia do próprio `from` (offset 0) três situações: já dentro do expediente → mantém o
  # instante original; antes da abertura → empurra para a abertura de hoje; depois do
  # fechamento → nil, para o laço seguir varrendo os próximos dias. Em qualquer outro dia
  # (offset > 0) a primeira abertura encontrada é o alvo.
  def resolve(offset, from_local, opening, closing)
    return opening if offset.positive?
    return @from if from_local.between?(opening, closing)
    return opening if from_local < opening

    nil
  end

  # Espelha o gate de Inbox#out_of_office?: sem working_hours_enabled?, working_now? é sempre
  # true e não há expediente a respeitar. Sem linhas de WorkingHour (não deveria ocorrer — o
  # after_create semeia as 7) também é no-op.
  def configured?
    @inbox&.working_hours_enabled? && schedule.present?
  end

  def schedule
    @schedule ||= @inbox ? @inbox.working_hours.index_by(&:day_of_week) : {}
  end

  def timezone
    ActiveSupport::TimeZone[@inbox.timezone] || Time.zone
  end
end
