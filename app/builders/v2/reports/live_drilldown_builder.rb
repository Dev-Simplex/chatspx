# As conversas por tras dos numeros da Visao geral (abertas, nao atendidas, sem atendente, pendentes).
#
# Recebe o MESMO recorte que o Api::V2::Accounts::LiveReportsController conta (conta, time, caixa), e aplica o
# mesmo escopo de cada numero, entao a lista fecha com ele. A ordem e de quem espera ha mais tempo primeiro.
class V2::Reports::LiveDrilldownBuilder
  PER_PAGE = 25
  CSV_LIMIT = 5_000
  METRICS = %w[open unattended unassigned pending].freeze

  def initialize(conversations, metric:, assignee_id: nil)
    @conversations = conversations
    @metric = metric.to_s
    @assignee_id = assignee_id
  end

  def supported?
    METRICS.include?(@metric)
  end

  def page(number)
    number = [number.to_i, 1].max
    {
      meta: { metric: @metric, total_count: scope.count, conversations_count: scope.count, page: number, per_page: PER_PAGE },
      payload: rows(offset: (number - 1) * PER_PAGE, limit: PER_PAGE)
    }
  end

  def to_csv
    CSVSafe.generate do |csv|
      csv << (I18n.t('reports.drilldown_csv.headers').values + [I18n.t('reports.drilldown_csv.value.waiting')])
      rows(offset: 0, limit: CSV_LIMIT).each do |row|
        csv << [row[:display_id], row[:contact_name], row[:inbox_name], row[:agent_name], row[:team_name],
                I18n.t("reports.drilldown_csv.status.#{row[:status]}", default: row[:status]),
                format_time(row[:created_at]), format_time(row[:value_at]), row[:value]]
      end
    end
  end

  private

  def scope
    @scope ||= begin
      relation = @metric == 'pending' ? @conversations.pending : @conversations.open
      relation = relation.unattended if @metric == 'unattended'
      relation = relation.unassigned if @metric == 'unassigned'
      # A linha "sem atendente" da tabela de agentes chega como assignee_id=none.
      relation = relation.where(assignee_id: @assignee_id == 'none' ? nil : @assignee_id) if @assignee_id.present?
      relation
    end
  end

  def rows(offset:, limit:)
    now = Time.current
    scope.includes(:contact, :inbox, :assignee, :team)
         .order(Arel.sql('COALESCE(conversations.waiting_since, conversations.created_at) ASC'), :id)
         .offset(offset).limit(limit).map { |conversation| row(conversation, now) }
  end

  def row(conversation, now)
    since = conversation.waiting_since || conversation.created_at
    {
      id: conversation.id, display_id: conversation.display_id, status: conversation.status,
      contact_name: conversation.contact&.name, inbox_name: conversation.inbox&.name,
      agent_name: conversation.assignee&.available_name, team_name: conversation.team&.name,
      created_at: conversation.created_at.to_i, value_at: since.to_i, value: (now - since).round
    }
  end

  def format_time(timestamp)
    timestamp && Time.zone.at(timestamp).strftime('%d/%m/%Y %H:%M')
  end
end
