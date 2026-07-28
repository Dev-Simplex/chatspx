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
#
# A rede de seguranca tinha um custo escondido: sendo SEM ESTADO, ela nao distinguia
# "vai resolver logo" de "esta preso ha 83 dias apontando para uma sessao FAILED".
# Um unico contact_inbox nessa situacao gerou 2.812 Net::ReadTimeout em 20 dias
# (GlitchTip issue 27) — 7 tentativas por hora, para sempre. Agora ha dois freios,
# ambos ANTES do enfileiramento:
#   1. sessao: so enfileira se a sessao da caixa estiver WORKING na WAHA
#      (Waha::SessionStatusCache, uma chamada de ~0,1s cacheada por 60s);
#   2. backoff: LID que ja falhou espera (Whatsapp::LidPhoneCache#cooling_down?),
#      1h no primeiro ciclo, ate 7 dias — e volta a ser tentado sozinho.
# Nada e truncado em silencio: as duas contagens vao para o log da execucao.
class Contacts::ResolveLidSweepJob < ApplicationJob
  queue_as :scheduled_jobs

  # Teto de seguranca por execucao. O excedente fica para a proxima rodada e e LOGADO
  # (nunca truncado em silencio).
  DEFAULT_MAX_PER_RUN = 1_000

  def perform(max_per_run = DEFAULT_MAX_PER_RUN)
    relation = stuck_contact_inboxes
    total = relation.count
    rows = relation.limit(max_per_run).pluck(
      'contact_inboxes.id', 'contact_inboxes.inbox_id', 'contact_inboxes.source_id', 'contacts.identifier'
    )
    @session_names = session_names_for(rows)

    stats = Hash.new(0)
    rows.each { |row| enqueue_or_skip(row, stats) }

    log_run(total, rows.size, max_per_run, stats)
  end

  private

  # Enfileira so o que tem chance de resolver. Os dois freios existem porque, ate
  # aqui, o sweep era sem estado: reenfileirava eternamente o mesmo contact_inbox,
  # 7 tentativas por hora, mesmo apontando para uma sessao morta ha 83 dias
  # (GlitchTip issue 27 — 2.812 timeouts em 20 dias, UM contact_inbox).
  def enqueue_or_skip(row, stats)
    contact_inbox_id, inbox_id, source_id, identifier = row
    session_name = @session_names[inbox_id]

    # Sessao que nao esta WORKING nao devolve 422 rapido: leva ~10s, acima do
    # timeout de 8s do ApiService. Uma chamada a GET /api/sessions (cacheada 60s)
    # cobre a execucao inteira, em vez de um timeout por contato.
    return skip(stats, :sessao_nao_working) unless Waha::SessionStatusCache.usable?(session_name)

    lid = source_id.to_s.end_with?('@lid') ? source_id : identifier
    return skip(stats, :backoff) if lid.present? && Whatsapp::LidPhoneCache.cooling_down?(session_name, lid)

    Contacts::ResolveLidJob.set(queue: :scheduled_jobs).perform_later(contact_inbox_id)
    stats[:reenfileirados] += 1
  end

  def skip(stats, reason)
    stats[reason] += 1
    nil
  end

  def session_names_for(rows)
    inbox_ids = rows.pluck(1).uniq
    return {} if inbox_ids.empty?

    Inbox.where(id: inbox_ids).pluck(:id, :waha_session_name).to_h
  end

  def log_run(total, picked, max_per_run, stats)
    remaining = [total - picked, 0].max
    Rails.logger.info(
      "[ResolveLidSweepJob] presos=#{total} reenfileirados=#{stats[:reenfileirados]} " \
      "pulados_sessao=#{stats[:sessao_nao_working]} pulados_backoff=#{stats[:backoff]} " \
      "restantes=#{remaining} teto=#{max_per_run}"
    )
  end

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
