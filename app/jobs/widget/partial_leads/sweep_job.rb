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
  # `:scheduled_jobs`, e nao `:low`. O Sidekiq desta base usa prioridade ESTRITA
  # (`config/sidekiq.yml`: "jobs in lower ranking queues will only be processed if there are
  # no jobs in higher ranking queues") e a `:low` fica abaixo da `:default`. O efeito ja foi
  # medido aqui e esta escrito em `config/schedule.yml`, na entrada do
  # `waha_refresh_groups_job`: "em producao carregada a :low quase nunca drenava". Agendar o
  # varredor numa fila que nao drena seria trocar um job que nunca roda por um job que roda
  # quando o sistema esta ocioso — e o aceite fala de materializar o lead, nao de tentar.
  queue_as :scheduled_jobs

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

  # `abandoned_at: nil` e o que impede a varredura infinita. O escopo antigo era so
  # `stale AND contact_id IS NULL`, e a linha que o servico nao consegue materializar (sem
  # canal de contato, sem ContactInbox de sessao) nunca preenche `contact_id` — entao ela
  # voltava aqui a CADA passagem do cron ate a retencao vencer. O servico agora confirma
  # `abandoned_at` mesmo quando nao materializa, e essa marca e a porta de saida do laco.
  def materialize_abandoned(account, settings)
    cutoff = settings.abandon_after_minutes.minutes.ago
    WidgetPartialLead.where(account_id: account.id).stale(cutoff)
                     .where(contact_id: nil, abandoned_at: nil)
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
