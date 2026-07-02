# Relatório de Atribuições por Agente. Para cada agente da conta, no período, conta:
#   - recebidas (total + quebra por origem: manual / automática / auto-assumida)
#   - feitas para outros (atribuições manuais em que o agente foi o AUTOR e o destino foi
#     outra pessoa) — o segundo lado do requisito ("quem atribuiu pra quem").
# Espelha o shape "contagem por agente" de V2::Reports::OutgoingMessagesCountBuilder.
# Fonte: conversation_assignment_histories (forward-only, escrito pelo AssignmentHistoryService).
class V2::Reports::AgentAssignmentBuilder
  include DateRangeHelper

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    load_counts
    account.account_users.includes(:user).map { |account_user| build_row(account_user) }
  end

  private

  def load_counts
    scope = ConversationAssignmentHistory.where(account_id: account.id)
    scope = scope.in_range(range) if range

    @received = scope.group(:assignee_id).count
    @received_manual = scope.where(source: :manual).group(:assignee_id).count
    @received_auto = scope.where(source: :auto_round_robin).group(:assignee_id).count
    @received_self = scope.where(source: :self_assigned).group(:assignee_id).count
    @made_to_others = made_to_others_counts(scope)
  end

  # Autoria só de atribuições manuais para OUTRA pessoa (self-assign não credita autoria).
  def made_to_others_counts(scope)
    scope.where(source: :manual)
         .where.not(assigned_by_id: nil)
         .where('assigned_by_id <> assignee_id')
         .group(:assigned_by_id).count
  end

  def build_row(account_user)
    uid = account_user.user_id
    {
      id: uid,
      name: account_user.user&.name,
      received_total: @received[uid].to_i,
      received_manual: @received_manual[uid].to_i,
      received_auto: @received_auto[uid].to_i,
      self_assigned: @received_self[uid].to_i,
      assigned_to_others: @made_to_others[uid].to_i
    }
  end
end
