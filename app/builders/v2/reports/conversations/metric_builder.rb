class V2::Reports::Conversations::MetricBuilder < V2::Reports::Conversations::BaseReportBuilder
  include DateRangeHelper

  def summary
    {
      conversations_count: count('conversations_count'),
      incoming_messages_count: count('incoming_messages_count'),
      outgoing_messages_count: count('outgoing_messages_count'),
      avg_first_response_time: count('avg_first_response_time'),
      avg_first_response_time_after_assignment: count('avg_first_response_time_after_assignment'),
      avg_resolution_time: count('avg_resolution_time'),
      resolutions_count: count('resolutions_count'),
      reply_time: count('reply_time'),
      p50_first_response_time: percentile_for('avg_first_response_time', 0.5),
      p90_first_response_time: percentile_for('avg_first_response_time', 0.9),
      p50_first_response_time_after_assignment: percentile_for('avg_first_response_time_after_assignment', 0.5),
      p90_first_response_time_after_assignment: percentile_for('avg_first_response_time_after_assignment', 0.9),
      first_response_count: event_count('avg_first_response_time'),
      first_response_after_assignment_count: event_count('avg_first_response_time_after_assignment')
    }
  end

  def bot_summary
    {
      bot_resolutions_count: count('bot_resolutions_count'),
      bot_handoffs_count: count('bot_handoffs_count')
    }
  end

  private

  def count(metric)
    builder_class(metric).new(account, builder_params(metric)).aggregate_value
  end

  def builder_params(metric)
    params.merge({ metric: metric })
  end

  def scope
    case params[:type].to_sym
    when :account
      account
    when :inbox
      account.inboxes.find(params[:id])
    when :agent
      account.users.find(params[:id])
    when :label
      account.labels.find(params[:id])
    when :team
      account.teams.find(params[:id])
    end
  end

  def percentile_for(metric, percentile)
    event_name = event_name_for(metric)
    return 0 unless event_name

    column = business_hours? ? 'value_in_business_hours' : 'value'
    event_scope(event_name).pick(
      Arel.sql("percentile_cont(#{percentile}) WITHIN GROUP (ORDER BY #{column})")
    ) || 0
  end

  def event_count(metric)
    event_name = event_name_for(metric)
    return 0 unless event_name

    event_scope(event_name).count
  end

  def event_scope(event_name)
    with_inbox_filter(scope.reporting_events.where(name: event_name, created_at: range, account_id: account.id))
  end

  def event_name_for(metric)
    {
      avg_first_response_time: 'first_response',
      avg_first_response_time_after_assignment: 'first_response_after_assignment',
      avg_resolution_time: 'conversation_resolved',
      reply_time: 'reply_time'
    }[metric.to_sym]
  end

  def business_hours?
    ActiveModel::Type::Boolean.new.cast(params[:business_hours])
  end
end
