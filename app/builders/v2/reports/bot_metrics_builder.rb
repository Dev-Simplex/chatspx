class V2::Reports::BotMetricsBuilder
  include DateRangeHelper
  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  def metrics
    {
      conversation_count: bot_conversations.count,
      message_count: bot_messages.count,
      resolution_rate: bot_resolution_rate.to_i,
      handoff_rate: bot_handoff_rate.to_i,
      signals: signals
    }
  end

  private

  # Semáforo das taxas do bot. Sem conversas com bot no período → sem sinais.
  def signals
    return [] if bot_conversations.count.zero?

    Reports::SignalSet.new(entries: [
                             { metric: :bot_resolution_rate, value: bot_resolution_rate.to_i },
                             { metric: :bot_handoff_rate, value: bot_handoff_rate.to_i }
                           ]).build
  end

  def bot_activated_inbox_ids
    @bot_activated_inbox_ids ||= account.inboxes.filter(&:active_bot?).map(&:id)
  end

  def bot_conversations
    @bot_conversations ||= account.conversations.where(inbox_id: bot_activated_inbox_ids).where(created_at: range)
  end

  def bot_messages
    @bot_messages ||= account.messages.outgoing.where(conversation_id: bot_conversations.ids).where(created_at: range)
  end

  def bot_resolutions_count
    account.reporting_events.joins(:conversation).select(:conversation_id).where(account_id: account.id, name: :conversation_bot_resolved,
                                                                                 created_at: range).distinct.count
  end

  def bot_handoffs_count
    account.reporting_events.joins(:conversation).select(:conversation_id).where(account_id: account.id, name: :conversation_bot_handoff,
                                                                                 created_at: range).distinct.count
  end

  def bot_resolution_rate
    return 0 if bot_conversations.count.zero?

    bot_resolutions_count.to_f / bot_conversations.count * 100
  end

  def bot_handoff_rate
    return 0 if bot_conversations.count.zero?

    bot_handoffs_count.to_f / bot_conversations.count * 100
  end
end
