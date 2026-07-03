# frozen_string_literal: true

class Kanban::FunnelItemsQueryService
  DEFAULT_LIMIT = 30
  MAX_LIMIT = 100

  def initialize(account:, funnel:, scope:, params:)
    @account = account
    @funnel = funnel
    @scope = scope
    @params = params
  end

  def perform
    query = apply_filters(scope)
    query = apply_cursor(query)
    query = query
            .joins(:conversation)
            .reorder('conversations.last_activity_at DESC, conversations.id DESC')

    records = query.limit(limit + 1).to_a
    has_more = records.size > limit
    records = records.first(limit) if has_more

    { items: records, meta: build_meta(records, has_more) }
  end

  private

  def build_meta(records, has_more)
    last_record = records.last
    next_cursor = (encode_cursor(cursor_timestamp(last_record), last_record.conversation_id) if has_more && last_record)
    {
      stage_id: parsed_stage_id,
      has_more: has_more,
      next_cursor: next_cursor,
      limit: limit,
      aggregates: stage_aggregates
    }
  end

  # Kanban v2 (Fase 2): sum/avg/count of numeric custom fields across the WHOLE
  # stage (not just the loaded page). Computed in SQL — only on the first page
  # (cursor blank) and only for numeric fields shown on the card.
  def stage_aggregates
    return {} if parsed_stage_id.blank? || params[:cursor].present?

    fields = funnel.funnel_custom_fields.numeric.on_card.to_a
    return {} if fields.empty?

    base = apply_filters(scope).joins(:conversation)
    fields.each_with_object({}) do |field, acc|
      summary = aggregate_field(base, field)
      acc[field.key] = summary if summary
    end
  end

  def aggregate_field(base, field)
    quoted_key = ActiveRecord::Base.connection.quote(field.attribute_key)
    value_sql = "conversations.custom_attributes ->> #{quoted_key}"
    numeric_guard = "#{value_sql} ~ '^-?[0-9]+(\\.[0-9]+)?$'"

    sum, count = base.pick(
      Arel.sql("COALESCE(SUM(CASE WHEN #{numeric_guard} THEN (#{value_sql})::numeric ELSE 0 END), 0)"),
      Arel.sql("COUNT(CASE WHEN #{numeric_guard} THEN 1 END)")
    )
    return nil if count.to_i.zero?

    total = sum.to_f
    { label: field.label, sum: total.round(2), avg: (total / count).round(2), count: count.to_i }
  end

  attr_reader :account, :funnel, :scope, :params

  def apply_filters(relation) # rubocop:disable Metrics/AbcSize
    filtered = relation

    filtered = filtered.by_stage(parsed_stage_id) if parsed_stage_id.present?

    if parsed_excluded_automation_type.present?
      filtered = filtered.joins(:funnel_stage).where.not(funnel_stages: { automation_type: parsed_excluded_automation_type })
    end

    inbox_ids = normalize_inbox_ids(funnel.inbox_ids)
    filtered = filtered.joins(:conversation).where(conversations: { inbox_id: inbox_ids }) if inbox_ids.any?

    filtered = filtered.joins(:conversation).where(conversations: { team_id: funnel.team_id }) if funnel.team_id.present?

    filtered = filtered.joins(:conversation).where(conversations: { account_id: account.id }) if account.present?

    filtered
  end

  def apply_cursor(relation)
    cursor_data = decode_cursor(params[:cursor])
    return relation unless cursor_data

    relation.joins(:conversation).where(
      '(conversations.last_activity_at, conversations.id) < (?, ?)',
      cursor_data[:last_activity_at],
      cursor_data[:id]
    )
  end

  def parsed_stage_id
    value = params[:stage_id]
    return nil if value.blank?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def parsed_excluded_automation_type
    value = params[:exclude_automation_type].to_s
    value.presence
  end

  def limit
    requested = parse_integer(params[:limit])
    return DEFAULT_LIMIT if requested.nil?

    requested.clamp(1, MAX_LIMIT)
  end

  def parse_integer(value)
    return nil if value.blank?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_inbox_ids(inbox_ids)
    return [] unless inbox_ids.is_a?(Array)

    inbox_ids.filter_map { |id| parse_integer(id) }.uniq
  end

  def decode_cursor(cursor)
    return nil if cursor.blank?

    raw = Base64.strict_decode64(cursor.to_s)
    data = JSON.parse(raw).with_indifferent_access
    parsed_time = Time.zone.parse(data[:last_activity_at].to_s)
    return nil if parsed_time.blank?

    { last_activity_at: parsed_time, id: data[:id].to_i }
  rescue ArgumentError, JSON::ParserError
    nil
  end

  def encode_cursor(last_activity_at, id)
    Base64.strict_encode64(
      {
        last_activity_at: last_activity_at.iso8601(3),
        id: id
      }.to_json
    )
  end

  def cursor_timestamp(record)
    record.conversation&.last_activity_at || record.conversation&.updated_at || record.updated_at || Time.zone.at(0)
  end
end
