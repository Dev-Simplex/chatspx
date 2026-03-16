class Api::V1::Accounts::AgentStatsController < Api::V1::Accounts::BaseController
  # Returns personal performance stats for the currently logged-in agent.
  # No admin role required — agents can only see their own data.
  # Uses direct queries instead of MetricBuilder to properly handle
  # agent-scoped metrics (incoming messages, resolutions, etc.)

  def show
    range = parse_range
    agent = current_user

    # Conversations assigned to this agent
    agent_conversations = Current.account.conversations.where(assignee_id: agent.id)
    agent_conversation_ids = agent_conversations.select(:id)

    # Outgoing messages sent BY this agent (sender_type = 'User', sender_id = agent.id)
    outgoing_count = Current.account.messages
                            .where(sender_type: 'User', sender_id: agent.id, created_at: range)
                            .where(message_type: :outgoing)
                            .count

    # Incoming messages ON conversations assigned to this agent
    incoming_count = Current.account.messages
                            .where(conversation_id: agent_conversation_ids, created_at: range)
                            .where(message_type: :incoming)
                            .count

    # Conversations resolved by this agent (reporting_event with user_id)
    resolutions_count = ReportingEvent.where(
      name: 'conversation_resolved',
      account_id: Current.account.id,
      user_id: agent.id,
      created_at: range
    ).count

    # Average resolution time for this agent
    avg_resolution_time = ReportingEvent.where(
      name: 'conversation_resolved',
      account_id: Current.account.id,
      user_id: agent.id,
      created_at: range
    ).average(:value).to_f.round

    # Average first response time for this agent
    avg_first_response_time = ReportingEvent.where(
      name: 'first_response',
      account_id: Current.account.id,
      user_id: agent.id,
      created_at: range
    ).average(:value).to_f.round

    # Conversations count (created in period and assigned to agent)
    conversations_count = agent_conversations.where(created_at: range).count

    render json: {
      conversations_count: conversations_count,
      incoming_messages_count: incoming_count,
      outgoing_messages_count: outgoing_count,
      resolutions_count: resolutions_count,
      avg_resolution_time: avg_resolution_time,
      avg_first_response_time: avg_first_response_time
    }
  end

  private

  def parse_range
    since_time = params[:since].present? ? Time.zone.at(params[:since].to_i) : Time.zone.today.beginning_of_day
    until_time = params[:until].present? ? Time.zone.at(params[:until].to_i) : Time.zone.now
    since_time..until_time
  end
end
