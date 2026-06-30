# frozen_string_literal: true

# Re-sweep agendado dos contatos/contact_inboxes que ficaram "presos" com @lid.
#
# Contexto do incidente: quando o servidor WAHA e migrado/reiniciado (ex.: a troca
# api.chatspx.app -> wapi.chatspx.app em ~2026-05-23), o cache LID->PN do WhatsApp
# zera. Os Contacts::ResolveLidJob que rodaram nesse intervalo esgotam as 7 tentativas
# e MORREM — e nada os reagenda. Resultado: identificadores @lid presos para sempre.
#
# Este job e a rede de seguranca: roda no cron, encontra o que sobrou com @lid e
# reenfileira a resolucao. Quando a WAHA reaprende o mapeamento (apos o
# Waha::RefreshGroupsJob/trafego), o contato preso e recuperado sozinho — algo que
# hoje NUNCA acontece.
#
# Idempotente: reenfileirar para um contact_inbox ja resolvido e no-op (o ResolveLidJob
# checa needs_resolution?). Reenfileira para fora da fila :high (usa :scheduled_jobs)
# para nao competir com a resolucao em tempo real disparada pelos webhooks.
class Contacts::ResolveLidSweepJob < ApplicationJob
  queue_as :scheduled_jobs

  # Teto de seguranca por execucao. O excedente fica para a proxima rodada e e LOGADO
  # (nunca truncado em silencio).
  DEFAULT_MAX_PER_RUN = 1_000

  def perform(max_per_run = DEFAULT_MAX_PER_RUN)
    relation = stuck_contact_inboxes
    total = relation.count

    ids = relation.limit(max_per_run).pluck('contact_inboxes.id')
    ids.each { |contact_inbox_id| Contacts::ResolveLidJob.set(queue: :scheduled_jobs).perform_later(contact_inbox_id) }

    remaining = [total - ids.size, 0].max
    Rails.logger.info(
      "[ResolveLidSweepJob] presos=#{total} reenfileirados=#{ids.size} restantes=#{remaining} teto=#{max_per_run}"
    )
  end

  private

  # contact_inboxes presos com @lid: ou o proprio source_id e @lid, ou o contato dono
  # ainda carrega @lid em identifier/name (lixo residual de uma resolucao parcial).
  # Restringe a inboxes WAHA (unica origem de LID) para nao enfileirar resolucao em
  # canais sem sessao — la o job seria no-op e o contato nunca sairia da varredura.
  def stuck_contact_inboxes
    waha_inbox_ids = Inbox.where.not(waha_session_name: [nil, '']).select(:id)

    ContactInbox
      .where(inbox_id: waha_inbox_ids)
      .joins(:contact)
      .where(
        'contact_inboxes.source_id LIKE :lid OR contacts.identifier LIKE :lid OR contacts.name LIKE :lid',
        lid: '%@lid'
      )
  end
end
