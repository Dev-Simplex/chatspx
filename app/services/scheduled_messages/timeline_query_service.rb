# frozen_string_literal: true

class ScheduledMessages::TimelineQueryService
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 100
  DEFAULT_PAST_WINDOW = 30.days
  DEFAULT_FUTURE_WINDOW = 30.days

  def initialize(scope:, params:)
    @scope = scope
    @params = params
  end

  def perform
    query = apply_filters(scope)
    query = apply_cursor(query)
    query = query.reorder('scheduled_messages.scheduled_at DESC, scheduled_messages.id DESC')

    rows = query.limit(limit + 1).to_a
    has_more = rows.length > limit
    rows = rows.first(limit) if has_more

    {
      items: rows,
      meta: {
        has_more: has_more,
        next_cursor: has_more ? encode_cursor(rows.last) : nil,
        limit: limit,
        status: requested_status.presence || 'all',
        from: from_time&.iso8601,
        to: to_time&.iso8601
      }
    }
  end

  private

  attr_reader :scope, :params

  def apply_filters(relation)
    filtered = relation
    filtered = filtered.where(conversation_id: parsed_conversation_id) if parsed_conversation_id.present?
    filtered = filtered.where(status: requested_status) if requested_status.present? && requested_status != 'all'
    filtered = filtered.where('scheduled_messages.scheduled_at >= ?', from_time) if from_time.present?
    filtered = filtered.where('scheduled_messages.scheduled_at <= ?', to_time) if to_time.present?
    filtered
  end

  def apply_cursor(relation)
    cursor = decode_cursor(params[:cursor])
    return relation if cursor.blank?

    relation.where(
      '(scheduled_messages.scheduled_at, scheduled_messages.id) < (?, ?)',
      cursor[:scheduled_at],
      cursor[:id]
    )
  end

  def parsed_conversation_id
    value = params[:conversation_id]
    return nil if value.blank?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def requested_status
    params[:status].to_s.strip.presence
  end

  def limit
    value = parse_integer(params[:limit])
    return DEFAULT_LIMIT if value.nil?

    value.clamp(1, MAX_LIMIT)
  end

  def from_time
    @from_time ||= parsed_time(params[:from]) || DEFAULT_PAST_WINDOW.ago
  end

  def to_time
    @to_time ||= parsed_time(params[:to]) || DEFAULT_FUTURE_WINDOW.from_now
  end

  def parsed_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_integer(value)
    return nil if value.blank?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def decode_cursor(cursor)
    return nil if cursor.blank?

    decoded = Base64.urlsafe_decode64(cursor.to_s)
    payload = JSON.parse(decoded)
    scheduled_at = Time.zone.parse(payload['scheduled_at'].to_s)
    id = payload['id'].to_i
    return nil if scheduled_at.blank? || id <= 0

    { scheduled_at: scheduled_at, id: id }
  rescue ArgumentError, JSON::ParserError
    nil
  end

  def encode_cursor(record)
    return nil if record.blank?

    Base64.urlsafe_encode64(
      {
        scheduled_at: record.scheduled_at&.iso8601(3),
        id: record.id
      }.to_json
    )
  end
end
