class MessageFinder
  MAX_PAGE_LIMIT = 100
  DEFAULT_PAGE_LIMIT = 20
  DEFAULT_AFTER_LIMIT = 100
  DEFAULT_BETWEEN_LIMIT = 1000

  attr_reader :has_more

  def initialize(conversation, params)
    @conversation = conversation
    @params = params
    @has_more = false
  end

  def perform
    @has_more = false
    current_messages
  end

  private

  def conversation_messages
    scope = @conversation.messages
                         .where(inbox_id: @conversation.inbox_id)
                         .includes(
                           { attachments: [{ file_attachment: [:blob] }] },
                           :sender,
                           :reactions,
                           sender: { avatar_attachment: [:blob] }
                         )
    apply_agent_isolation(scope)
  end

  # Isolamento POR AGENTE depende de QUEM olha — por isso (diferente do team isolation,
  # que vive na association conversation.messages) o filtro mora aqui, onde Current.user
  # e conhecido. Mesmo acoplamento a Current.user ja usado em Message#reopened_by_contact?.
  # Listagens do widget/public API nao tem Current.user -> o filtro vira no-op (seguro).
  def apply_agent_isolation(scope)
    restriction_id = AgentMessageIsolation.restriction_id_for_inbox(
      @conversation.inbox, Current.user, @conversation.account_id
    )
    AgentMessageIsolation.filter_messages(scope, restriction_id)
  end

  def messages
    scope = conversation_messages
    scope = scope.where.not('private = ? OR message_type = ?', true, 2) if @params[:filter_internal_messages].present?
    scope = scope.where(starred: true) if starred_filter?
    scope
  end

  # Accepts boolean-ish values: true / "true" / "1". Anything else is ignored
  # (the filter is opt-in; absence means "return everything").
  def starred_filter?
    return false if @params[:starred].nil?

    ActiveModel::Type::Boolean.new.cast(@params[:starred])
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    messages.reorder('created_at asc, id asc').where('id > ?', after_id).limit(after_limit)
  end

  def messages_before(before_id)
    fetch_cursor_page(messages.reorder('created_at desc, id desc').where('id < ?', before_id), page_limit).reverse
  end

  def messages_between(after_id, before_id)
    messages.reorder('created_at asc, id asc').where('id >= ? AND id < ?', after_id, before_id).limit(between_limit)
  end

  def messages_latest
    fetch_cursor_page(messages.reorder('created_at desc, id desc'), page_limit).reverse
  end

  def fetch_cursor_page(relation, limit)
    records = relation.limit(limit + 1).to_a
    @has_more = records.size > limit
    records.first(limit)
  end

  def page_limit
    parsed_limit = @params[:limit].to_i
    return DEFAULT_PAGE_LIMIT if parsed_limit <= 0

    [parsed_limit, MAX_PAGE_LIMIT].min
  end

  def after_limit
    parsed_limit = @params[:limit].to_i
    return DEFAULT_AFTER_LIMIT if parsed_limit <= 0

    [parsed_limit, MAX_PAGE_LIMIT].min
  end

  def between_limit
    parsed_limit = @params[:limit].to_i
    return DEFAULT_BETWEEN_LIMIT if parsed_limit <= 0

    [parsed_limit, MAX_PAGE_LIMIT].min
  end
end
