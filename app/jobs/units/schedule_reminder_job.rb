# frozen_string_literal: true

# Avisa quem atende que uma regra de agenda da unidade está chegando (feriado,
# manutenção, temporada). Roda uma vez por dia; a data já avisada fica em
# `last_reminded_on`, então rodar de novo não manda o aviso duas vezes.
class Units::ScheduleReminderJob < ApplicationJob
  queue_as :low

  def perform
    UnitException.where.not(reminder_days_before: nil).includes(unit: :account).find_each do |regra|
      avisar(regra)
    end
  end

  private

  def avisar(regra)
    unit = regra.unit
    return if unit.blank?

    # "Daqui a N dias" é contado no fuso da unidade: em Cuiabá o dia vira uma hora
    # depois, e o aviso da véspera não pode sair no dia errado.
    hoje = Time.current.in_time_zone(unit.timezone).to_date
    alvo = hoje + regra.reminder_days_before.days
    return if regra.last_reminded_on == alvo
    return unless Units::ScheduleEvaluator.rule_on?(regra, alvo)

    entregar(unit, regra, alvo)
    # update_column de propósito: gravar a marca do aviso não pode reprovar numa
    # validação da regra nem disparar callback.
    regra.update_column(:last_reminded_on, alvo) # rubocop:disable Rails/SkipsModelValidations
  end

  def entregar(unit, regra, alvo)
    Current.account = unit.account
    AdministratorNotifications::UnitScheduleMailer
      .upcoming_rule(unit, regra, alvo, destinatarios(unit))
      .deliver_later
  ensure
    Current.account = nil
  end

  # Administradores da conta e quem atende nas caixas daquela unidade — é quem vai
  # estar na linha no dia.
  def destinatarios(unit)
    admins = unit.account.administrators.pluck(:email)
    agentes = User.joins(:inbox_members).where(inbox_members: { inbox_id: unit.inboxes.select(:id) }).pluck(:email)
    (admins + agentes).uniq
  end
end
