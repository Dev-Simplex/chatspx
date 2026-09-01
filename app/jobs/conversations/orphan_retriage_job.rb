# Re-triagem de conversas órfãs (Fase C / C10 — D-12, DC-8).
# Re-executa DIRETAMENTE as regras de triagem (ConditionsFilterService + ActionService) —
# NUNCA re-dispatch de CONVERSATION_CREATED (acordaria webhooks/notificações/relatórios).
# 1 re-triagem + 1 notificação por EPISÓDIO de orfandade (dedupe em additional_attributes).
class Conversations::OrphanRetriageJob < ApplicationJob
  queue_as :low
  DEFAULT_RETRIAGE_AFTER_MINUTES = 15
  BATCH_LIMIT = 100

  # Conversa cujo dono está trabalhando o lead FORA do SPX (engajou no card do Vista) tem a
  # cara exata de uma órfã — open, sem assignee, sem espelho captain — mas não é. Sem este
  # filtro, cada lead designado vira uma notificação `conversation_orphaned` por administrador,
  # o que afoga justamente o sinal que existe pra achar órfã de verdade.
  #
  # A comparação com `last_activity_at` é o que impede a exclusão de virar permanente: se o
  # cliente voltar a falar DEPOIS do engajamento, a conversa é órfã de novo e volta pro fluxo.
  # Também mantém a exclusão fora do BATCH_LIMIT, senão as designadas ocupariam o lote e as
  # órfãs reais ficariam sem re-triagem.
  TRABALHADA_FORA_DO_SPX = <<~SQL.squish.freeze
    NOT EXISTS (
      SELECT 1 FROM distribuicao_logs dl
      WHERE dl.conversation_id = conversations.id
        AND dl.status = 'engajado'
        AND dl.encerrado_em >= conversations.last_activity_at
    )
  SQL

  def perform(account)
    threshold = retriage_after(account).minutes.ago
    # órfã = open + SEM humano + SEM espelho captain (os DOIS nils — scope :unassigned não basta;
    # janela em last_activity_at: cobre conversa que ficou órfã DEPOIS, ex. user deletado)
    #
    # `joins(:contact)` (INNER JOIN) exclui conversa cujo contato não existe mais (resíduo de
    # consolidação feita com delete/update_columns). Essas são órfãs de DADO, não de atribuição:
    # não há quem notificar nem o que triar, e o `update!` do carimbo estourava RecordInvalid
    # (Contact must exist) abortando o lote inteiro.
    account.conversations.open
           .joins(:contact)
           .where(assignee_id: nil).without_captain_assignee
           .where('conversations.last_activity_at < ?', threshold)
           .where(TRABALHADA_FORA_DO_SPX)
           .limit(BATCH_LIMIT)
           .each do |conversation|
      # Uma conversa problemática não pode abortar o lote: sem isto, a exceção sobe pelo
      # `each` e as conversas seguintes ficam sem re-triagem até alguém notar (o cron
      # rodou 288x/dia por semanas assim). Mesmo tratamento do loop de regras abaixo.
      process_orphan(conversation, account)
    rescue StandardError => e
      # Nomeia a conversa no log: sem o id, "uma conversa do lote falhou" não é
      # diagnosticável, e este laço roda 288x/dia.
      Rails.logger.error("[OrphanRetriageJob] account=#{account.id} conversation=#{conversation.id} " \
                         "falhou: #{e.class}: #{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
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

    # ORDEM IMPORTA: grava o marcador ANTES de notificar. Notificar primeiro e falhar no
    # marcador (conversa inválida) repetia push/e-mail para todos os admins a cada tick do
    # cron, para sempre — o dedupe nunca chegava a existir. Se o marcador não pode ser
    # gravado, o alerta não sai: melhor um alerta perdido do que spam infinito.
    mark_alerted(conversation)
    notify_admins(conversation, account)
  end

  def mark_alerted(conversation)
    conversation.update!(additional_attributes:
      conversation.additional_attributes.merge('orphan_alerted_at' => Time.current.iso8601))
  end

  # Re-execução DIRETA das regras de triagem (NUNCA re-dispatch de CONVERSATION_CREATED — acordaria
  # webhooks/notificações/relatórios). Filosofia do AssignmentKickJob: re-executa o entry com re-check.
  #
  # F1.4 (modo FILA): a re-triagem pode rotear a órfã pra um time (assign_team), MAS não pode
  # reanexar a IA (assign_ai_agent) — senão a conversa volta pra IA e a fila por time some.
  # Quem adota "toda conversa tem dono" liga `ia_reentra_orfa` e a re-triagem passa a poder
  # dar a órfã de volta pra IA, que lê o histórico e decide (Account#ia_reentra_orfa_enabled?).
  # Current.skip_ai_agent_assignment desliga só a action assign_ai_agent. Setado POR REGRA
  # (não antes do loop), porque AutomationRules::ActionService#perform faz Current.reset no ensure.
  def retriage(conversation, account)
    skip_ai = !account.ia_reentra_orfa_enabled?

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
