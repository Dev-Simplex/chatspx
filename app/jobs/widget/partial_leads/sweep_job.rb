# frozen_string_literal: true

# Bloco 4.18 — o varredor do lead incompleto. Duas tarefas, por conta:
#
#   1. ABANDONO: registro parado ha mais tempo que a janela e sem conclusao vira lead de
#      verdade no painel (Widget::PartialLeads::MaterializeService).
#   2. RETENCAO: registro parcial mais velho que a retencao e APAGADO. E dado pessoal de
#      quem nao concluiu — guardar "por via das duvidas" e exatamente o que a LGPD nao
#      permite. O default esta declarado em Widget::PartialLeads::Settings.
#
# O expurgo roda MESMO com a captura desligada: quem desliga a chave espera que o que ja
# foi coletado pare de existir, nao que congele para sempre.
class Widget::PartialLeads::SweepJob < ApplicationJob
  queue_as :low

  # Teto por execucao: o varredor nao pode virar uma transacao gigante numa conta com
  # muito trafego. O que sobrar e apanhado na proxima passagem.
  BATCH = 500

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.blank?

    settings = Widget::PartialLeads::Settings.new(account)
    materialize_abandoned(account, settings) if settings.enabled?
    purge_expired(account, settings)
  end

  private

  def materialize_abandoned(account, settings)
    cutoff = settings.abandon_after_minutes.minutes.ago
    WidgetPartialLead.where(account_id: account.id).stale(cutoff).where(contact_id: nil)
                     .limit(BATCH).find_each do |lead|
      Widget::PartialLeads::MaterializeService.new(lead).perform
    end
  end

  def purge_expired(account, settings)
    cutoff = settings.retention_days.days.ago
    WidgetPartialLead.where(account_id: account.id)
                     .where(last_answered_at: ...cutoff)
                     .limit(BATCH)
                     .destroy_all
  end
end
