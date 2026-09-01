class V2::Reports::Conversations::BaseReportBuilder
  pattr_initialize :account, :params

  private

  AVG_METRICS = %w[
    avg_first_response_time
    avg_first_response_time_after_assignment
    avg_resolution_time
    reply_time
  ].freeze
  COUNT_METRICS = %w[
    conversations_count
    incoming_messages_count
    outgoing_messages_count
    resolutions_count
    bot_resolutions_count
    bot_handoffs_count
  ].freeze

  # Mesmo recorte por caixa do BaseTimeseriesBuilder — ver comentario la.
  def inbox_ids
    @inbox_ids ||= Array(params[:inbox_id]).reject(&:blank?).map(&:to_i)
  end

  def with_inbox_filter(relation)
    return relation if inbox_ids.blank?

    relation.where(inbox_id: inbox_ids)
  end

  def builder_class(metric)
    case metric
    when *AVG_METRICS
      V2::Reports::Timeseries::AverageReportBuilder
    when *COUNT_METRICS
      V2::Reports::Timeseries::CountReportBuilder
    end
  end

  def log_invalid_metric
    Rails.logger.error "ReportBuilder: Invalid metric - #{params[:metric]}"

    {}
  end
end
