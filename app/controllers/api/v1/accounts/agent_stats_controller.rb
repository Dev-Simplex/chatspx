class Api::V1::Accounts::AgentStatsController < Api::V1::Accounts::BaseController
  # Returns personal performance stats for the currently logged-in agent.
  # No admin role required — agents can only see their own data.
  # Uses direct queries instead of MetricBuilder to properly handle
  # agent-scoped metrics (incoming messages, resolutions, etc.)

  def show # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    range = parse_range
    agent = current_user
    account_id = Current.account.id

    agent_conversation_ids = Current.account.conversations.where(assignee_id: agent.id).select(:id)

    # Combine message counts into a single query
    message_counts = Current.account.messages.where(created_at: range)
                            .where(
                              '(sender_type = ? AND sender_id = ? AND message_type = ?) OR ' \
                              '(conversation_id IN (?) AND message_type = ?)',
                              'User', agent.id, Message.message_types[:outgoing],
                              agent_conversation_ids, Message.message_types[:incoming]
                            )
                            .pick(
                              Arel.sql("COUNT(*) FILTER (WHERE sender_type = 'User' AND message_type = 1)"),
                              Arel.sql('COUNT(*) FILTER (WHERE message_type = 0)')
                            )
    outgoing_count, incoming_count = message_counts

    # Combine reporting event queries into a single query
    reporting_stats = ReportingEvent.where(account_id: account_id, user_id: agent.id, created_at: range)
                                    .pick(
                                      Arel.sql("COUNT(*) FILTER (WHERE name = 'conversation_resolved')"),
                                      Arel.sql("COALESCE(AVG(value) FILTER (WHERE name = 'conversation_resolved'), 0)"),
                                      Arel.sql("COALESCE(AVG(value) FILTER (WHERE name = 'first_response'), 0)")
                                    )
    resolutions_count, avg_resolution_time, avg_first_response_time = reporting_stats

    conversations_count = Current.account.conversations.where(assignee_id: agent.id, created_at: range).count

    render json: {
      conversations_count: conversations_count,
      incoming_messages_count: incoming_count.to_i,
      outgoing_messages_count: outgoing_count.to_i,
      resolutions_count: resolutions_count.to_i,
      avg_resolution_time: avg_resolution_time.to_f.round,
      avg_first_response_time: avg_first_response_time.to_f.round
    }
  end

  private

  def parse_range
    since_time = params[:since].present? ? Time.zone.at(params[:since].to_i) : Time.zone.today.beginning_of_day
    until_time = params[:until].present? ? Time.zone.at(params[:until].to_i) : Time.zone.now
    since_time..until_time
  end
end
