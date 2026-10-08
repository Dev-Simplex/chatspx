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

  # Matriz "quem atribuiu pra quem": pares (autor → destino) de atribuições
  # manuais a outra pessoa, com contagem. O front monta a grade a partir disto.
  def matrix
    pairs = made_to_others_pairs
    return [] if pairs.empty?

    names = account.users.where(id: pairs.keys.flatten.uniq).pluck(:id, :name).to_h
    entries = pairs.map do |(from_id, to_id), count|
      {
        from_id: from_id, from_name: names[from_id] || "##{from_id}",
        to_id: to_id, to_name: names[to_id] || "##{to_id}",
        count: count
      }
    end
    entries.sort_by { |pair| -pair[:count] }
  end

  # As atribuicoes por tras de um numero da tabela, com o mesmo recorte das contagens.
  # received_other = tudo o que nao e manual, rodizio ou "pegou para si" (IA, automacao, API, origem desconhecida).
  HISTORY_KINDS = %w[received_total received_manual received_auto self_assigned received_other assigned_to_others pair].freeze
  KNOWN_SOURCES = %i[manual auto_round_robin self_assigned].freeze

  SOURCE_BY_KIND = { 'received_manual' => :manual, 'received_auto' => :auto_round_robin, 'self_assigned' => :self_assigned }.freeze

  def history_scope(kind:, user_id:, to_id: nil)
    kind = kind.to_s
    return base_scope.where(source: SOURCE_BY_KIND[kind], assignee_id: user_id) if SOURCE_BY_KIND.key?(kind)

    case kind
    when 'received_total' then base_scope.where(assignee_id: user_id)
    when 'received_other' then base_scope.where(assignee_id: user_id).where.not(source: KNOWN_SOURCES)
    when 'assigned_to_others' then made_to_others_relation(base_scope).where(assigned_by_id: user_id)
    when 'pair' then made_to_others_relation(base_scope).where(assigned_by_id: user_id, assignee_id: to_id)
    end
  end

  private

  # Escopo base do histórico: período + filtros opcionais de time e inbox.
  # team_id é coluna direta no histórico; inbox exige join com conversations.
  def base_scope
    scope = ConversationAssignmentHistory.where(account_id: account.id)
    scope = scope.in_range(range) if range
    scope = scope.where(team_id: params[:team_id]) if params[:team_id].present?
    scope = scope.joins(:conversation).where(conversations: { inbox_id: params[:inbox_id] }) if params[:inbox_id].present?
    scope
  end

  # Colunas qualificadas: com o join de inbox (conversations), assignee_id/team_id
  # existem nas duas tabelas — group/where cru daria "column reference is ambiguous".
  def assignee_col
    'conversation_assignment_histories.assignee_id'
  end

  def author_col
    'conversation_assignment_histories.assigned_by_id'
  end

  def load_counts
    scope = base_scope
    @received = scope.group(assignee_col).count
    @received_manual = scope.where(source: :manual).group(assignee_col).count
    @received_auto = scope.where(source: :auto_round_robin).group(assignee_col).count
    @received_self = scope.where(source: :self_assigned).group(assignee_col).count
    @made_to_others = made_to_others_counts(scope)
  end

  # Autoria só de atribuições manuais para OUTRA pessoa (self-assign não credita autoria).
  def made_to_others_counts(scope)
    made_to_others_relation(scope).group(author_col).count
  end

  def made_to_others_pairs
    made_to_others_relation(base_scope).group(author_col, assignee_col).count
  end

  def made_to_others_relation(scope)
    scope.where(source: :manual)
         .where.not(assigned_by_id: nil)
         .where("#{author_col} <> #{assignee_col}")
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
