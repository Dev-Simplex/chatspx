class SearchService # rubocop:disable Metrics/ClassLength
  pattr_initialize [:current_user!, :current_account!, :params!, :search_type!]

  def perform
    case search_type
    when 'Message'
      { messages: filter_messages }
    when 'Conversation'
      { conversations: filter_conversations }
    when 'Contact'
      { contacts: filter_contacts }
    when 'Article'
      { articles: filter_articles }
    else
      { contacts: filter_contacts, messages: filter_messages, conversations: filter_conversations, articles: filter_articles }
    end
  end

  private

  def accessable_inbox_ids
    @accessable_inbox_ids ||= @current_user.assigned_inboxes.pluck(:id)
  end

  # SUPERVISÃO DE TIME (D2): o supervisor acha na busca as conversas dos times que
  # supervisiona mesmo em caixas das quais não é membro. Vazio => tudo abaixo é no-op.
  def supervised_team_ids
    @supervised_team_ids ||= TeamSupervision.team_ids(current_user, current_account)
  end

  # Subconsulta (e não pluck) p/ não carregar o time inteiro em memória; só inteiros do banco.
  def supervised_conversations_sql
    Conversation.where(account_id: current_account.id, team_id: supervised_team_ids).select(:id).to_sql
  end

  def scope_conversations_to_access(relation)
    return relation.where(inbox_id: accessable_inbox_ids) if supervised_team_ids.empty?

    relation.where('conversations.inbox_id IN (:ids) OR conversations.team_id IN (:teams)',
                   ids: accessable_inbox_ids, teams: supervised_team_ids)
  end

  # Do lado das mensagens não há team_id da conversa: o alcance vira subconsulta.
  def scope_messages_to_access(relation)
    return relation.where(inbox_id: accessable_inbox_ids) if supervised_team_ids.empty?

    relation.where("messages.inbox_id IN (:ids) OR messages.conversation_id IN (#{supervised_conversations_sql})",
                   ids: accessable_inbox_ids)
  end

  def conversation_accessible?(conversation)
    accessable_inbox_ids.include?(conversation.inbox_id) || supervised_team_ids.include?(conversation.team_id)
  end

  def search_query
    @search_query ||= params[:q].to_s.strip
  end

  def filter_conversations
    conversations_query = scope_conversations_to_access(current_account.conversations)
                          .joins('INNER JOIN contacts ON conversations.contact_id = contacts.id')
                          .where("cast(conversations.display_id as text) ILIKE :search OR contacts.name ILIKE :search OR contacts.email
                            ILIKE :search OR contacts.phone_number ILIKE :search OR contacts.identifier ILIKE :search", search: "%#{search_query}%")

    if current_account.feature_enabled?('advanced_search')
      conversations_query = apply_time_filter(conversations_query,
                                              'conversations.last_activity_at')
    end

    @conversations = conversations_query.includes(:contact, :inbox, :assignee, :team, contact: :avatar_attachment)
                                        .order('conversations.created_at DESC')
                                        .page(params[:page])
                                        .per(15)
  end

  def filter_messages
    @messages = if use_gin_search
                  filter_messages_with_gin
                elsif should_run_advanced_search?
                  advanced_search_with_fallback
                else
                  filter_messages_with_like
                end
  end

  def advanced_search_with_fallback
    advanced_search
  rescue Faraday::ConnectionFailed, Searchkick::Error, Elasticsearch::Transport::Transport::Error => e
    Rails.logger.warn("Elasticsearch unavailable, falling back to SQL search: #{e.message}")
    use_gin_search ? filter_messages_with_gin : filter_messages_with_like
  end

  def filter_messages_with_gin
    base_query = message_base_query
    base_query = apply_message_filters(base_query)

    if search_query.present?
      # Use the @@ operator with to_tsquery for better GIN index utilization
      # Convert search query to tsquery format with prefix matching

      # Use this if we wanna match splitting the words
      # split_query = search_query.split.map { |term| "#{term} | #{term}:*" }.join(' & ')

      # This will do entire sentence matching using phrase distance operator
      tsquery = search_query.split.join(' <-> ')

      # Apply the text search using the GIN index
      base_query.where('content @@ to_tsquery(?)', tsquery)
                .reorder('created_at DESC')
                .page(params[:page])
                .per(15)
    else
      base_query.reorder('created_at DESC')
                .page(params[:page])
                .per(15)
    end
  end

  def filter_messages_with_like
    base_query = message_base_query
    base_query = apply_message_filters(base_query)
    base_query.where('messages.content ILIKE :search', search: "%#{search_query}%")
              .reorder('created_at DESC')
              .page(params[:page])
              .per(15)
  end

  def message_base_query
    query = scope_messages_to_access(current_account.messages)
            .where('created_at >= ?', 3.months.ago)

    # Filter by conversation_id if provided
    if params[:conversation_id].present?
      conv_display_id = params[:conversation_id].to_i
      # Verify user has access to this conversation (frontend sends display_id, not internal id)
      conversation = current_account.conversations.find_by(display_id: conv_display_id)
      query = if conversation && conversation_accessible?(conversation)
                query.where(conversation_id: conversation.id)
              else
                # If conversation_id is provided but user doesn't have access,
                # return empty result (use a condition that will never match)
                query.where('1 = 0')
              end
    end

    apply_agent_isolation(query)
  end

  # Isolamento por agente: na busca de mensagens, um agente não-admin não acha conteúdo de
  # outro agente em inbox com a flag ON. Admin/sem restrição/nenhum inbox isolado → no-op.
  # Usa subquery de inbox_id (sem JOIN) para não tornar `created_at` ambíguo no resto da query.
  def apply_agent_isolation(query)
    agent_id = AgentMessageIsolation.viewer_restriction_id(current_user, current_account)
    return query if agent_id.nil?

    isolated_inbox_ids = current_account.inboxes.where(agent_message_isolation: true).pluck(:id)
    return query if isolated_inbox_ids.empty?

    # Supervisor do time da conversa vê todas as bolhas dela (D2) — a cláusula só
    # aparece quando há supervisão, senão a query fica idêntica à de antes.
    supervised_or = supervised_team_ids.any? ? " OR messages.conversation_id IN (#{supervised_conversations_sql})" : ''
    query.where(
      "messages.agent_id IS NULL OR messages.agent_id = :uid OR messages.inbox_id NOT IN (:isolated)#{supervised_or}",
      uid: agent_id, isolated: isolated_inbox_ids
    )
  end

  def apply_message_filters(query)
    return query unless current_account.feature_enabled?('advanced_search')

    query = apply_time_filter(query, 'messages.created_at')
    query = apply_sender_filter(query)
    apply_inbox_id_filter(query)
  end

  def apply_sender_filter(query)
    sender_type, sender_id = parse_from_param(params[:from])
    return query unless sender_type && sender_id

    query.where(sender_type: sender_type, sender_id: sender_id)
  end

  def parse_from_param(from_param)
    return [nil, nil] unless from_param&.match?(/\A(contact|agent):\d+\z/)

    type, id = from_param.split(':')
    sender_type = type == 'agent' ? 'User' : 'Contact'
    [sender_type, id.to_i]
  end

  def apply_inbox_id_filter(query)
    return query if params[:inbox_id].blank?

    inbox_id = params[:inbox_id].to_i
    return query if inbox_id.zero?
    return query unless validate_inbox_access(inbox_id)

    query.where(inbox_id: inbox_id)
  end

  def validate_inbox_access(inbox_id)
    return true if should_skip_inbox_filtering?

    accessable_inbox_ids.include?(inbox_id)
  end

  def use_gin_search
    current_account.feature_enabled?('search_with_gin')
  end

  def should_run_advanced_search?
    false
  end

  def should_skip_inbox_filtering?
    false
  end

  def filter_contacts
    contacts_query = current_account.contacts.where(
      "name ILIKE :search OR email ILIKE :search OR phone_number
      ILIKE :search OR identifier ILIKE :search", search: "%#{search_query}%"
    )

    contacts_query = apply_time_filter(contacts_query, 'last_activity_at') if current_account.feature_enabled?('advanced_search')

    @contacts = contacts_query.resolved_contacts.order_on_last_activity_at('desc').page(params[:page]).per(15)
  end

  def filter_articles
    articles_query = current_account.articles.text_search(search_query)
    articles_query = apply_time_filter(articles_query, 'updated_at') if current_account.feature_enabled?('advanced_search')

    @articles = articles_query.page(params[:page]).per(15)
  end

  def apply_time_filter(query, column_name)
    return query if params[:since].blank? && params[:until].blank?

    query = query.where("#{column_name} >= ?", cap_since_time(params[:since])) if params[:since].present?
    query = query.where("#{column_name} <= ?", cap_until_time(params[:until])) if params[:until].present?
    query
  end

  def cap_since_time(since_param)
    max_lookback = 90.days.ago
    requested_time = Time.zone.at(since_param.to_i)

    # Silently cap to max_lookback if requested time is too far back
    [requested_time, max_lookback].max
  end

  def cap_until_time(until_param)
    max_future = 90.days.from_now
    requested_time = Time.zone.at(until_param.to_i)

    [requested_time, max_future].min
  end
end
