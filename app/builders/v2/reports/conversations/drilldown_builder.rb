# As conversas por tras de um numero do relatorio ("241 resolvidas: quais sao?").
#
# Usa o MESMO recorte que calcula o numero do cartao (`drilldown_scope` dos builders de serie temporal), entao a
# lista sempre fecha com ele: contagem de conversas lista as conversas; de mensagens, as conversas com quantas
# mensagens cada uma; e as metricas de tempo e de resolucao listam cada evento, com o valor que entrou na media.
class V2::Reports::Conversations::DrilldownBuilder < V2::Reports::Conversations::BaseReportBuilder
  PER_PAGE = 25
  CSV_LIMIT = 5_000
  MESSAGE_METRICS = %w[incoming_messages_count outgoing_messages_count].freeze
  EVENT_METRICS = (AVG_METRICS + %w[resolutions_count]).freeze
  SUPPORTED_METRICS = (%w[conversations_count] + MESSAGE_METRICS + EVENT_METRICS).freeze

  def supported?
    SUPPORTED_METRICS.include?(metric)
  end

  def page(number)
    number = [number.to_i, 1].max
    {
      meta: { metric: metric, total_count: total_count, conversations_count: conversations_count,
              page: number, per_page: PER_PAGE },
      payload: rows(offset: (number - 1) * PER_PAGE, limit: PER_PAGE)
    }
  end

  # As primeiras linhas, na mesma ordem do painel (o anexo do PDF usa).
  def top(limit)
    rows(offset: 0, limit: limit)
  end

  def to_csv
    CSVSafe.generate do |csv|
      csv << (I18n.t('reports.drilldown_csv.headers').values + [I18n.t("reports.drilldown_csv.value.#{metric}")])
      top(CSV_LIMIT).each do |row|
        csv << [row[:display_id], row[:contact_name], row[:inbox_name], row[:agent_name], row[:team_name],
                I18n.t("reports.drilldown_csv.status.#{row[:status]}", default: row[:status]),
                format_time(row[:created_at]), format_time(row[:value_at]), row[:value]]
      end
    end
  end

  # Quantos itens o numero conta: conversas, mensagens ou eventos (a "base" da media).
  def total_count
    @total_count ||= scope.count
  end

  def conversations_count
    @conversations_count ||= metric == 'conversations_count' ? total_count : scope.distinct.count(:conversation_id)
  end

  private

  def metric
    params[:metric].to_s
  end

  def scope
    @scope ||= builder_class(metric).new(account, params).drilldown_scope.unscope(:order)
  end

  def rows(offset:, limit:)
    if metric == 'conversations_count'
      conversation_rows(offset, limit)
    elsif MESSAGE_METRICS.include?(metric)
      message_rows(offset, limit)
    else
      event_rows(offset, limit)
    end
  end

  def conversation_rows(offset, limit)
    scope.includes(:contact, :inbox, :assignee, :team).order(created_at: :desc, id: :desc).offset(offset).limit(limit)
         .map { |conversation| row(conversation, value: nil, value_at: conversation.created_at, agent: conversation.assignee) }
  end

  # Mais mensagens primeiro: e a conversa que mais pesou no numero.
  def message_rows(offset, limit)
    counts = scope.group(:conversation_id).order(Arel.sql('COUNT(*) DESC'), :conversation_id).offset(offset).limit(limit).count
    conversations = Conversation.includes(:contact, :inbox, :assignee, :team).where(id: counts.keys).index_by(&:id)
    counts.filter_map do |conversation_id, count|
      conversation = conversations[conversation_id]
      conversation && row(conversation, value: count, value_at: conversation.last_activity_at, agent: conversation.assignee)
    end
  end

  # Tempo: o mais demorado primeiro (e o que o gestor quer achar). Resolucao (contagem): a mais recente primeiro.
  def event_rows(offset, limit)
    order = metric == 'resolutions_count' ? { created_at: :desc, id: :desc } : { value_column => :desc, :id => :desc }
    scope.includes(:user, conversation: %i[contact inbox team assignee]).order(order).offset(offset).limit(limit)
         .filter_map do |event|
      event.conversation && row(event.conversation, value: event.public_send(value_column)&.round, value_at: event.created_at, agent: event.user)
    end
  end

  def value_column
    params[:business_hours].present? ? :value_in_business_hours : :value
  end

  def row(conversation, value:, value_at:, agent:)
    {
      id: conversation.id, display_id: conversation.display_id, status: conversation.status,
      contact_name: conversation.contact&.name, inbox_name: conversation.inbox&.name,
      agent_name: agent&.available_name, team_name: conversation.team&.name,
      created_at: conversation.created_at.to_i, value_at: value_at&.to_i, value: value
    }
  end

  def format_time(timestamp)
    timestamp && Time.zone.at(timestamp).strftime('%d/%m/%Y %H:%M')
  end
end
