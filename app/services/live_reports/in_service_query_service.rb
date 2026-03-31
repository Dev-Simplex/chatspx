# frozen_string_literal: true

class LiveReports::InServiceQueryService # rubocop:disable Metrics/ClassLength
  DEFAULT_LIMIT = 5
  MAX_LIMIT = 20
  VALID_SCOPES = %w[agent waiting].freeze

  def initialize(account:, params: {})
    @account = account
    @params = params
  end

  def overview
    scope = base_scope

    {
      generated_at: Time.zone.now.iso8601,
      totals: {
        in_service: scope.count,
        waiting: waiting_scope(scope).distinct.count(:id),
        agents_with_conversations: scope.where.not(assignee_id: nil).distinct.count(:assignee_id)
      },
      agents: grouped_agent_metrics(scope)
    }
  end

  def conversations # rubocop:disable Metrics/AbcSize
    scoped = apply_scope(base_scope).includes(contact: { avatar_attachment: [:blob] })
    scoped = apply_cursor(scoped)
    scoped = scoped.order(last_activity_at: :desc, id: :desc)

    records = scoped.limit(per_page + 1).to_a
    has_more = records.size > per_page
    records = records.first(per_page) if has_more

    preloaded = Conversations::ListPreloader.call(records)
    preload_last_non_activity_attachments(preloaded)

    {
      scope: scope_param,
      assignee_id: parsed_assignee_id,
      meta: {
        next_cursor: has_more && records.last ? encode_cursor(records.last.last_activity_at, records.last.id) : nil,
        has_more: has_more
      },
      payload: records.map { |conversation| serialize_conversation(conversation, preloaded) }
    }
  end

  def conversation_validation_error
    return 'invalid scope' unless VALID_SCOPES.include?(scope_param)
    return 'assignee_id is required for scope=agent' if scope_param == 'agent' && parsed_assignee_id.nil?

    nil
  end

  private

  attr_reader :account, :params

  def base_scope
    scope = account.conversations.where(status: [Conversation.statuses[:open], Conversation.statuses[:pending]])
    scope = scope.where(team_id: parsed_team_id) if parsed_team_id.present?
    scope
  end

  def waiting_scope(scope)
    scope.where(status: Conversation.statuses[:pending]).or(scope.where(assignee_id: nil))
  end

  def apply_scope(scope)
    case scope_param
    when 'agent'
      scope.where(assignee_id: parsed_assignee_id)
    when 'waiting'
      waiting_scope(scope)
    else
      scope.none
    end
  end

  def apply_cursor(scope)
    cursor_data = decode_cursor(params[:cursor])
    return scope unless cursor_data

    scope.where(
      '(conversations.last_activity_at, conversations.id) < (?, ?)',
      cursor_data[:last_activity_at],
      cursor_data[:id]
    )
  end

  def grouped_agent_metrics(scope)
    rows = scope.where.not(assignee_id: nil).group(:assignee_id).pluck(
      :assignee_id,
      Arel.sql('COUNT(*)::int'),
      Arel.sql("COUNT(*) FILTER (WHERE status = #{Conversation.statuses[:open]})::int"),
      Arel.sql("COUNT(*) FILTER (WHERE status = #{Conversation.statuses[:pending]})::int")
    )

    rows.map do |assignee_id, in_service_count, open_count, pending_count|
      {
        assignee_id: assignee_id,
        in_service: in_service_count.to_i,
        open: open_count.to_i,
        pending: pending_count.to_i
      }
    end.sort_by { |row| [-row[:in_service], row[:assignee_id]] } # rubocop:disable Style/MultilineBlockChain
  end

  def serialize_conversation(conversation, preloaded)
    last_message = safe_preloaded_message(preloaded&.last_messages, conversation.id)
    last_non_activity_message = safe_preloaded_message(preloaded&.last_non_activity_messages, conversation.id)
    display_message = last_non_activity_message || last_message
    contact = safe_conversation_contact(conversation)

    {
      id: conversation.display_id,
      status: conversation.status,
      contact_name: contact_name(contact),
      contact_avatar: safe_contact_avatar(contact),
      last_message: safe_last_message_text(display_message),
      last_message_time: safe_last_message_time(conversation, display_message),
      last_message_status: safe_last_message_status(last_message),
      unread_count: safe_unread_count(preloaded&.unread_counts, conversation.id)
    }
  end

  def contact_name(contact)
    return nil unless contact

    contact.name.presence || contact.identifier.presence || contact.email.presence
  rescue StandardError
    nil
  end

  def last_message_text(message)
    return nil unless message
    return message.content if message.content.present?

    attachment_type = safe_attachment_type(message)
    case attachment_type
    when 'image'
      'Sent an image'
    when 'audio'
      'Sent an audio'
    when 'file'
      'Sent a file'
    when nil
      nil
    else
      'Sent an attachment'
    end
  end

  def last_message_status(message)
    return 'sent' unless message
    return 'read' if message.read_at.present?
    return 'sent' if message.outgoing?

    'sent'
  end

  def safe_last_message_text(message)
    last_message_text(message)
  rescue StandardError
    nil
  end

  def safe_last_message_status(message)
    last_message_status(message)
  rescue StandardError
    'sent'
  end

  def safe_last_message_time(conversation, display_message) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    (display_message&.created_at || conversation.last_activity_at || conversation.updated_at || conversation.created_at)&.to_i
  rescue StandardError
    (conversation.last_activity_at || conversation.updated_at || conversation.created_at)&.to_i
  end

  def safe_unread_count(unread_counts, conversation_id)
    unread_counts[conversation_id].to_i
  rescue StandardError
    0
  end

  def safe_conversation_contact(conversation)
    conversation.contact
  rescue StandardError
    nil
  end

  def safe_preloaded_message(message_map, conversation_id)
    return nil unless message_map.respond_to?(:[])

    message_map[conversation_id]
  rescue StandardError
    nil
  end

  def safe_contact_avatar(contact)
    return '' unless contact

    contact.avatar_url
  rescue StandardError
    ''
  end

  def safe_attachment_type(message)
    message.attachments.first&.file_type
  rescue StandardError
    nil
  end

  def preload_last_non_activity_attachments(preloaded)
    records = preloaded.last_non_activity_messages.values.compact
    return if records.empty?

    ActiveRecord::Associations::Preloader.new(
      records: records,
      associations: [{ attachments: [{ file_attachment: [:blob] }] }]
    ).call
  end

  def parsed_assignee_id
    @parsed_assignee_id ||= parse_integer(params[:assignee_id])
  end

  def parsed_team_id
    @parsed_team_id ||= parse_integer(params[:team_id])
  end

  def scope_param
    params[:scope].to_s
  end

  def per_page
    requested = parse_integer(params[:limit])
    return DEFAULT_LIMIT if requested.nil?

    requested.clamp(1, MAX_LIMIT)
  end

  def decode_cursor(cursor)
    return nil if cursor.blank?

    raw = Base64.strict_decode64(cursor)
    data = JSON.parse(raw).with_indifferent_access
    time = Time.zone.parse(data[:last_activity_at].to_s)
    return nil if time.blank?

    { last_activity_at: time, id: data[:id].to_i }
  rescue ArgumentError, JSON::ParserError
    nil
  end

  def encode_cursor(last_activity_at, id)
    Base64.strict_encode64({ last_activity_at: last_activity_at.iso8601(3), id: id }.to_json)
  end

  def parse_integer(value)
    return nil if value.blank?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end
end
