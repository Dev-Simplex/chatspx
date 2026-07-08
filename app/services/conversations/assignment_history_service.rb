# Grava um registro estruturado sempre que o responsável (assignee) de uma conversa muda.
# Chamado do hook central AssignmentHandler#process_assignment_changes (after_commit), onde o
# ator ainda está em mãos (Current.user / Current.executed_by). Best-effort (RNF1): qualquer
# falha é engolida e logada — NUNCA quebra nem atrasa a atribuição em si.
class Conversations::AssignmentHistoryService
  def initialize(conversation)
    @conversation = conversation
  end

  def record_change!
    now = Time.current

    # Fecha o intervalo aberto anterior desta conversa (se houver).
    ConversationAssignmentHistory
      .where(conversation_id: @conversation.id, unassigned_at: nil)
      .update_all(unassigned_at: now) # rubocop:disable Rails/SkipsModelValidations

    assignee_id = @conversation.assignee_id
    return if assignee_id.nil? # desatribuição: só fecha o intervalo, sem nova linha

    source = derive_source(assignee_id)
    ConversationAssignmentHistory.create!(
      account_id: @conversation.account_id,
      conversation_id: @conversation.id,
      assignee_id: assignee_id,
      team_id: @conversation.team_id,
      assigned_by_id: actor_id_for(source),
      source: source,
      assigned_at: now
    )
  rescue StandardError => e
    Rails.logger.error("[assignment_history] conversation=#{@conversation&.id} #{e.class}: #{e.message}")
  end

  private

  # A origem é derivada do contexto de execução. Contexto de automação/round-robin tem
  # prioridade sobre um Current.user ambiente (ex.: agente que dispara uma automação que
  # reatribui) — o sinal de "não foi um humano quem decidiu" é mais forte.
  def derive_source(assignee_id)
    case Current.executed_by
    when AutomationRule
      return :automation
    when AssignmentPolicy, Inbox
      return :auto_round_robin
    end

    if Current.user.is_a?(User)
      return :self_assigned if Current.user.id == assignee_id

      return :manual
    end

    # Current.user presente mas não é User (ex.: token de AgentBot) → handoff de bot.
    return :bot if Current.user.present?

    :unknown
  end

  # Só atribuições humanas (manual/self) creditam autoria. Auto/automação/bot ficam sem autor.
  def actor_id_for(source)
    return Current.user&.id if %w[manual self_assigned].include?(source.to_s)

    nil
  end
end
