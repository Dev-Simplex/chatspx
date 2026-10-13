# As atribuicoes por tras de um numero do relatorio de Atribuicoes ("Carlos recebeu 12: quais?").
# O recorte vem do proprio V2::Reports::AgentAssignmentBuilder#history_scope, entao a lista fecha com a tabela.
class V2::Reports::AssignmentDrilldownBuilder
  PER_PAGE = 25
  CSV_LIMIT = 5_000

  def initialize(account:, params:, kind:, user_id:, to_id: nil)
    @kind = kind.to_s
    @scope = V2::Reports::AgentAssignmentBuilder.new(account: account, params: params)
                                                .history_scope(kind: @kind, user_id: user_id, to_id: to_id)
  end

  def supported?
    V2::Reports::AgentAssignmentBuilder::HISTORY_KINDS.include?(@kind) && !@scope.nil?
  end

  def page(number)
    number = [number.to_i, 1].max
    total = @scope.count
    {
      meta: { metric: @kind, total_count: total, conversations_count: @scope.distinct.count(:conversation_id),
              page: number, per_page: PER_PAGE },
      payload: rows(offset: (number - 1) * PER_PAGE, limit: PER_PAGE)
    }
  end

  def to_csv
    CSVSafe.generate do |csv|
      csv << I18n.t('reports.assignment_csv.headers').values
      rows(offset: 0, limit: CSV_LIMIT).each do |row|
        csv << [row[:display_id], row[:contact_name], row[:inbox_name], row[:agent_name], row[:assigned_by_name],
                I18n.t("reports.assignment_csv.source.#{row[:source]}", default: row[:source]), row[:team_name],
                row[:value_at] && Time.zone.at(row[:value_at]).strftime('%d/%m/%Y %H:%M')]
      end
    end
  end

  private

  def rows(offset:, limit:)
    @scope.includes(:assignee, :assigned_by, :team, conversation: %i[contact inbox])
          .order(assigned_at: :desc, id: :desc).offset(offset).limit(limit)
          .filter_map { |history| history.conversation && row(history) }
  end

  def row(history)
    conversation = history.conversation
    {
      id: conversation.id, display_id: conversation.display_id, status: conversation.status,
      contact_name: conversation.contact&.name, inbox_name: conversation.inbox&.name,
      agent_name: history.assignee&.available_name, team_name: history.team&.name,
      assigned_by_name: history.assigned_by&.available_name, source: history.source,
      created_at: conversation.created_at.to_i, value_at: history.assigned_at.to_i, value: nil
    }
  end
end
