class AdministratorNotifications::UnitScheduleMailer < AdministratorNotifications::BaseMailer
  # Aviso de que uma regra de agenda da unidade vai cair daqui a alguns dias — o
  # feriado da filial chega antes ao time do que ao cliente.
  def upcoming_rule(unit, rule, date, recipients)
    return if recipients.blank?

    subject = "#{unit.name}: #{rule.name} em #{I18n.l(date, format: :long, locale: :pt_BR)}"
    send_notification(
      subject,
      to: recipients,
      action_url: settings_url('units'),
      meta: {
        unidade: unit.name,
        regra: rule.name,
        data: I18n.l(date, format: :long, locale: :pt_BR),
        efeito: rule.closed_all_day? ? 'fechada o dia todo' : faixa(rule)
      }
    )
  end

  private

  def faixa(rule)
    "aberta das #{hhmm(rule.open_hour, rule.open_minutes)} às #{hhmm(rule.close_hour, rule.close_minutes)}"
  end

  def hhmm(hora, minuto)
    format('%<hora>02d:%<minuto>02d', hora: hora.to_i, minuto: minuto.to_i)
  end
end
