class V2::Reports::ChannelSummaryBuilder
  include DateRangeHelper

  pattr_initialize [:account!, :params!]

  def build
    conversations_by_channel_and_status.transform_values { |status_counts| build_channel_stats(status_counts) }
  end

  private

  def inbox_ids
    @inbox_ids ||= Array(params[:inbox_id]).reject(&:blank?).map(&:to_i)
  end

  def conversations_by_channel_and_status
    scope = account.conversations
                   .joins(:inbox)
                   .where(created_at: range)
    scope = scope.where(inbox_id: inbox_ids) if inbox_ids.present?

    scope
      .group('inboxes.channel_type', 'conversations.status')
      .count
      .each_with_object({}) do |((channel_type, status), count), grouped|
      grouped[channel_type] ||= {}
      grouped[channel_type][status] = count
    end
  end

  def build_channel_stats(status_counts)
    open_count = status_counts['open'] || 0
    resolved_count = status_counts['resolved'] || 0
    pending_count = status_counts['pending'] || 0
    snoozed_count = status_counts['snoozed'] || 0

    {
      open: open_count,
      resolved: resolved_count,
      pending: pending_count,
      snoozed: snoozed_count,
      total: open_count + resolved_count + pending_count + snoozed_count
    }
  end
end
