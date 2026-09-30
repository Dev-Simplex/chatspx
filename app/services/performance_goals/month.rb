# CHAT-177: o "mes" das metas e sempre o dia 1, no fuso de relatorios da conta.
module PerformanceGoals::Month
  module_function

  def current(account)
    Time.current.in_time_zone(account.reporting_timezone.presence || Time.zone.name).to_date.beginning_of_month
  end

  # 'AAAA-MM' -> dia 1 daquele mes; ausente ou invalido -> mes corrente.
  def parse(value, account)
    Date.strptime(value.to_s, '%Y-%m')
  rescue Date::Error
    current(account)
  end
end
