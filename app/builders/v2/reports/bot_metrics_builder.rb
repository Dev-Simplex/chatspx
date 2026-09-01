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

  # Recorte por caixa: das caixas com bot, fica so a escolhida (se houver escolha).
  def inbox_ids
    @inbox_ids ||= Array(params[:inbox_id]).reject(&:blank?).map(&:to_i)
  end

  def bot_activated_inbox_ids
    @bot_activated_inbox_ids ||= begin
      ids = account.inboxes.filter(&:active_bot?).map(&:id)
      inbox_ids.present? ? ids & inbox_ids : ids
    end
  end

  def bot_conversations
    @bot_conversations ||= account.conversations.where(inbox_id: bot_activated_inbox_ids).where(created_at: range)
  end

  def bot_messages
    @bot_messages ||= account.messages.outgoing.where(conversation_id: bot_conversations.ids).where(created_at: range)
  end

  def bot_resolutions_count
    bot_event_count(:conversation_bot_resolved)
  end

  def bot_handoffs_count
    bot_event_count(:conversation_bot_handoff)
  end

  # As duas taxas precisam do mesmo recorte do denominador (bot_conversations),
  # senao a tela mostra "resolucao de 300%" ao filtrar uma caixa.
  def bot_event_count(event_name)
    scope = account.reporting_events.joins(:conversation)
                   .select(:conversation_id)
                   .where(account_id: account.id, name: event_name, created_at: range)
    scope = scope.where(conversations: { inbox_id: inbox_ids }) if inbox_ids.present?
    scope.distinct.count
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
