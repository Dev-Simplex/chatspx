require 'rails_helper'

# O que este job decide é QUAL regra avisar e EM QUE data — o envio em si é do mailer,
# que no ambiente de teste não sai (sem SMTP_ADDRESS) e ainda passa pela fila. Por isso
# a asserção é sobre a chamada ao mailer, não sobre ActionMailer::Base.deliveries.
RSpec.describe Units::ScheduleReminderJob do
  let(:account) { create(:account) }
  let(:unit) { create(:unit, account: account, timezone: 'America/Sao_Paulo') }
  let(:hoje) { Time.current.in_time_zone(unit.timezone).to_date }
  let(:mailer) { instance_double(ActionMailer::MessageDelivery, deliver_later: true) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  before do
    allow(AdministratorNotifications::UnitScheduleMailer).to receive(:upcoming_rule).and_return(mailer)
  end

  def regra(atributos = {})
    unit.exceptions.create!({ name: 'Feriado', starts_on: hoje + 1.day, closed_all_day: true }.merge(atributos))
  end

  it 'avisa quando a regra cai daqui a exatamente os dias configurados' do
    alvo = regra(reminder_days_before: 1)

    described_class.perform_now

    expect(AdministratorNotifications::UnitScheduleMailer)
      .to have_received(:upcoming_rule).with(unit, alvo, hoje + 1.day, array_including(admin.email))
    expect(alvo.reload.last_reminded_on).to eq(hoje + 1.day)
  end

  it 'não avisa duas vezes a mesma data — rodar de novo é no-op' do
    regra(reminder_days_before: 1)
    described_class.perform_now
    described_class.perform_now

    expect(AdministratorNotifications::UnitScheduleMailer).to have_received(:upcoming_rule).once
  end

  it 'ignora regra sem lembrete configurado' do
    regra(reminder_days_before: nil)

    described_class.perform_now

    expect(AdministratorNotifications::UnitScheduleMailer).not_to have_received(:upcoming_rule)
  end

  it 'não avisa quando a regra cai em outro dia que não o alvo' do
    regra(starts_on: hoje + 5.days, reminder_days_before: 1)

    described_class.perform_now

    expect(AdministratorNotifications::UnitScheduleMailer).not_to have_received(:upcoming_rule)
  end

  it 'segue a repetição: regra semanal avisa a próxima ocorrência' do
    amanha = hoje + 1.day
    regra(starts_on: amanha - 7.days, frequency: :semanal, weekdays: [amanha.wday], reminder_days_before: 1)

    described_class.perform_now

    expect(AdministratorNotifications::UnitScheduleMailer)
      .to have_received(:upcoming_rule).with(unit, anything, amanha, anything)
  end

  it 'conta os dias no fuso da unidade' do
    unidade_cuiaba = create(:unit, account: account, timezone: 'America/Cuiaba')
    hoje_cuiaba = Time.current.in_time_zone('America/Cuiaba').to_date
    unidade_cuiaba.exceptions.create!(name: 'Manutenção', starts_on: hoje_cuiaba + 3.days,
                                      closed_all_day: true, reminder_days_before: 3)

    described_class.perform_now

    expect(AdministratorNotifications::UnitScheduleMailer)
      .to have_received(:upcoming_rule).with(unidade_cuiaba, anything, hoje_cuiaba + 3.days, anything)
  end
end
