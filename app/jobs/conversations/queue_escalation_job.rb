# Vigia da fila por time (Fase F3 — decisão F-5 do plano fila-por-time-handoff).
# SOMENTE em contas no modo "Atribuição obrigatória" (reply_assignment_gate).
#
# Varre as conversas "aguardando atendimento" na fila de um time:
#   open + assignee_id nil + sem espelho captain (without_captain_assignee) + team_id presente
# e ESCALA (notifica os admins da conta) quando:
#   - a conversa está aguardando há mais de N minutos (config, default 10) sem ninguém puxar; OU
#   - o time da conversa NÃO tem nenhum agente ONLINE (escala já, mesmo antes dos N min).
#
# Escalar = notificar admins + manter a conversa visível na fila. NÃO muda atribuição,
# NÃO atribui ninguém. Dedup: escala UMA vez por conversa (custom_attributes['fila_escalada_em']);
# se um humano assume (ou a IA recaptura), a conversa sai do escopo e o marcador é limpo.
#
# Molde de estilo: Conversations::OrphanRetriageJob. Notificação: NotificationBuilder
# (precedente SlaEvent#create_notifications / OrphanRetriageJob#notify_admins).
class Conversations::QueueEscalationJob < ApplicationJob
  queue_as :low
  DEFAULT_ESCALATE_AFTER_MINUTES = 10
  BATCH_LIMIT = 100

  def perform(account)
    return unless account.reply_assignment_gate_enabled?

    online_user_ids = fetch_online_agent_ids(account)
    threshold = escalate_after(account).minutes.ago

    queued_conversations(account).find_each(batch_size: BATCH_LIMIT) do |conversation|
      process(conversation, account, online_user_ids, threshold)
    end
  end

  private

  # Fila por time: open + sem dono humano + sem espelho captain + com time.
  def queued_conversations(account)
    account.conversations.open
           .where(assignee_id: nil)
           .where.not(team_id: nil)
           .without_captain_assignee
  end

  def escalate_after(account)
    (account.queue_escalation_after.presence || DEFAULT_ESCALATE_AFTER_MINUTES).to_i
  end

  # Reusa o padrão de InboxAgentAvailability#fetch_online_agent_ids.
  def fetch_online_agent_ids(account)
    OnlineStatusTracker.get_available_users(account.id)
                       .select { |_id, status| status.to_s == 'online' }
                       .keys
                       .map(&:to_i)
  end

  def process(conversation, account, online_user_ids, threshold)
    return if already_escalated?(conversation)

    return unless escalate?(conversation, online_user_ids, threshold)

    notify_admins(conversation, account)
    mark_escalated(conversation)
  end

  # Escala se: (a) o time não tem ninguém online (escala já, mesmo antes dos N min), OU
  #            (b) está aguardando há mais de N min.
  def escalate?(conversation, online_user_ids, threshold)
    team_offline?(conversation, online_user_ids) || waiting_too_long?(conversation, threshold)
  end

  def team_offline?(conversation, online_user_ids)
    return true if online_user_ids.empty?

    team_member_ids = conversation.team.members.pluck(:id)
    !team_member_ids.intersect?(online_user_ids)
  end

  def waiting_too_long?(conversation, threshold)
    conversation.last_activity_at < threshold
  end

  def already_escalated?(conversation)
    conversation.custom_attributes['fila_escalada_em'].present?
  end

  def mark_escalated(conversation)
    conversation.update!(custom_attributes:
      conversation.custom_attributes.merge('fila_escalada_em' => Time.current.iso8601))
  end

  # Reusa conversation_orphaned (já tem flags/email/push/i18n/settings UI) — "conversa
  # precisa de atenção". Precedente exato: OrphanRetriageJob#notify_admins.
  def notify_admins(conversation, account)
    account.administrators.each do |admin|
      NotificationBuilder.new(
        notification_type: 'conversation_orphaned',
        user: admin, account: account, primary_actor: conversation
      ).perform
    end
  end
end
