# Re-triagem de conversas órfãs (Fase C / C10 — D-12, DC-8).
# Re-executa DIRETAMENTE as regras de triagem (ConditionsFilterService + ActionService) —
# NUNCA re-dispatch de CONVERSATION_CREATED (acordaria webhooks/notificações/relatórios).
# 1 re-triagem + 1 notificação por EPISÓDIO de orfandade (dedupe em additional_attributes).
class Conversations::OrphanRetriageJob < ApplicationJob
  queue_as :low
  DEFAULT_RETRIAGE_AFTER_MINUTES = 15
  BATCH_LIMIT = 100

  def perform(account)
    threshold = retriage_after(account).minutes.ago
    # órfã = open + SEM humano + SEM espelho captain (os DOIS nils — scope :unassigned não basta;
    # janela em last_activity_at: cobre conversa que ficou órfã DEPOIS, ex. user deletado)
    account.conversations.open
           .where(assignee_id: nil).without_captain_assignee
           .where('conversations.last_activity_at < ?', threshold)
           .limit(BATCH_LIMIT)
           .each { |conversation| process_orphan(conversation, account) }
  end

  private

  def retriage_after(account)
    (account.orphan_retriage_after.presence || DEFAULT_RETRIAGE_AFTER_MINUTES).to_i
  end

  # 1 re-triagem + 1 notificação POR EPISÓDIO (DC-8): dedupe via additional_attributes;
  # episódio reseta quando há atividade nova depois do último alerta.
  def process_orphan(conversation, account)
    alerted_at = conversation.additional_attributes['orphan_alerted_at']
    return if alerted_at.present? && Time.zone.parse(alerted_at) >= conversation.last_activity_at

    retriage(conversation, account)
    return unless still_orphan?(conversation)

    notify_admins(conversation, account)
    conversation.update!(additional_attributes:
      conversation.additional_attributes.merge('orphan_alerted_at' => Time.current.iso8601))
  end

  # Re-execução DIRETA das regras de triagem (NUNCA re-dispatch de CONVERSATION_CREATED — acordaria
  # webhooks/notificações/relatórios). Filosofia do AssignmentKickJob: re-executa o entry com re-check.
  #
  # F1.4 (modo FILA): a re-triagem pode rotear a órfã pra um time (assign_team), MAS não pode
  # reanexar a IA (assign_ai_agent) — senão a conversa volta pra IA e a fila por time some.
  # Current.skip_ai_agent_assignment desliga só a action assign_ai_agent. Setado POR REGRA
  # (não antes do loop), porque AutomationRules::ActionService#perform faz Current.reset no ensure.
  def retriage(conversation, account)
    skip_ai = account.reply_assignment_gate_enabled?

    account.automation_rules.where(event_name: 'conversation_created', active: true).find_each do |rule|
      conversation.reload
      break unless still_orphan?(conversation)
      next unless AutomationRules::ConditionsFilterService.new(rule, conversation, {}).perform

      service = AutomationRules::ActionService.new(rule, account, conversation)
      Current.skip_ai_agent_assignment = true if skip_ai # depois do new (constructor seta executed_by)
      service.perform
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
  end

  def still_orphan?(conversation)
    conversation.reload
    conversation.open? && conversation.assignee_id.nil? &&
      !conversation.assignee_agent_bot&.captain?
  end

  # Precedente exato: SlaEvent#create_notifications (sla_event.rb:64-86)
  def notify_admins(conversation, account)
    account.administrators.each do |admin|
      NotificationBuilder.new(
        notification_type: 'conversation_orphaned',
        user: admin, account: account, primary_actor: conversation
      ).perform
    end
  end
end
