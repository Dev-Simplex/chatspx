class ConversationFinder # rubocop:disable Metrics/ClassLength
  attr_reader :current_user, :current_account, :params

  DEFAULT_STATUS = 'open'.freeze
  SORT_OPTIONS = {
    'last_activity_at_asc' => %w[sort_on_last_activity_at asc],
    'last_activity_at_desc' => %w[sort_on_last_activity_at desc],
    'created_at_asc' => %w[sort_on_created_at asc],
    'created_at_desc' => %w[sort_on_created_at desc],
    'priority_asc' => %w[sort_on_priority asc],
    'priority_desc' => %w[sort_on_priority desc],
    'waiting_since_asc' => %w[sort_on_waiting_since asc],
    'waiting_since_desc' => %w[sort_on_waiting_since desc],
    'priority_desc_created_at_asc' => %w[sort_on_priority_created_at desc],

    # To be removed in v3.5.0
    'latest' => %w[sort_on_last_activity_at desc],
    'sort_on_created_at' => %w[sort_on_created_at asc],
    'sort_on_priority' => %w[sort_on_priority desc],
    'sort_on_waiting_since' => %w[sort_on_waiting_since asc]
  }.with_indifferent_access
  # assumptions
  # inbox_id if not given, take from all conversations, else specific to inbox
  # assignee_type if not given, take 'all'
  # conversation_status if not given, take 'open'

  # response of this class will be of type
  # {conversations: [array of conversations], count: {...}, next_cursor: string|null}

  # params
  # assignee_type, inbox_id, :status, :cursor, :limit

  def initialize(current_user, params)
    @current_user = current_user
    @current_account = current_user.account
    @is_admin = Current.account_user&.administrator?
    @params = params
  end

  def perform
    set_up

    counts = compute_all_counts
    assigned_count = counts[:all_count] - counts[:unassigned_count]

    filter_by_assignee_type if @assignee_type.present?
    convs, next_cursor = fetch_conversations

    {
      conversations: convs,
      count: {
        mine_count: counts[:mine_count],
        assigned_count: assigned_count,
        unassigned_count: counts[:unassigned_count],
        all_count: counts[:all_count],
        unattended_assigned_to_me_count: counts[:unattended_mine_count],
        unattended_unassigned_count: counts[:unattended_unassigned_count],
        unattended_all_count: counts[:unattended_all_count]
      },
      next_cursor: next_cursor
    }
  end

  def perform_counts_only
    set_up

    counts = compute_all_counts
    assigned_count = counts[:all_count] - counts[:unassigned_count]

    {
      count: {
        mine_count: counts[:mine_count],
        assigned_count: assigned_count,
        unassigned_count: counts[:unassigned_count],
        all_count: counts[:all_count],
        unattended_assigned_to_me_count: counts[:unattended_mine_count],
        unattended_unassigned_count: counts[:unattended_unassigned_count],
        unattended_all_count: counts[:unattended_all_count]
      }
    }
  end

  def perform_meta_only
    set_up

    mine_count, unassigned_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }
    }
  end

  private

  def set_up
    set_inboxes
    set_team
    set_assignee_type

    find_all_conversations
    filter_by_status unless params[:q]
    filter_by_team
    filter_by_conversation_type if params[:conversation_type]
    filter_by_labels
    filter_by_query
    filter_by_source_id
    filter_by_date_range
  end

  def set_inboxes
    @inbox_ids = if params[:inbox_id]
                   @current_user.assigned_inboxes.where(id: params[:inbox_id])
                 else
                   @current_user.assigned_inboxes.pluck(:id)
                 end
  end

  def set_assignee_type
    @assignee_type = params[:assignee_type]
  end

  def set_team
    parsed_team_id = Integer(params[:team_id], exception: false)

    if parsed_team_id.present? && parsed_team_id.positive?
      @team = current_account.teams.find_by(id: parsed_team_id)
      @team_ids = @team ? [@team.id] : []
    elsif !@is_admin && current_user.teams.any?
      @team = nil
      @team_ids = current_user.teams.pluck(:id)
    else
      @team = nil
      @team_ids = []
    end
  end

  def find_conversation_by_inbox
    @conversations = current_account.conversations

    # Exclude private chat conversation from all listings (invisible to everyone)
    if PrivateChat::Config.enabled? && PrivateChat::Config.conversation_id.present?
      @conversations = @conversations.where.not(id: PrivateChat::Config.conversation_id)
    end

    return unless params[:inbox_id]

    @conversations = @conversations.where(inbox_id: @inbox_ids)
  end

  def find_all_conversations
    find_conversation_by_inbox
    # Apply permission-based filtering
    @conversations = Conversations::PermissionFilterService.new(
      @conversations,
      current_user,
      current_account
    ).perform
    filter_blocked_contacts
    @conversations
  end

  def filter_by_assignee_type
    case @assignee_type
    when 'me'
      @conversations = @conversations.assigned_to(current_user)
    when 'unassigned'
      @conversations = @conversations.unassigned
    when 'assigned'
      @conversations = @conversations.assigned
    end
    @conversations
  end

  def filter_by_conversation_type
    case @params[:conversation_type]
    when 'mention'
      @conversations = @conversations.where(id: current_account.mentions.where(user: current_user).select(:conversation_id))
    when 'participating'
      @conversations = current_user.participating_conversations.where(account_id: current_account.id)
    when 'unattended'
      @conversations = @conversations.unattended
    end
    @conversations
  end

  def filter_by_query
    query = params[:q].is_a?(String) ? params[:q] : params[:q].to_s
    return if query.blank?

    allowed_message_types = [Message.message_types[:incoming], Message.message_types[:outgoing]]
    @conversations = @conversations.where(
      'EXISTS (SELECT 1 FROM messages WHERE messages.conversation_id = conversations.id ' \
      'AND messages.content ILIKE :search AND messages.message_type IN (:types))',
      search: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%",
      types: allowed_message_types
    )
  end

  def filter_by_status
    return if params[:status] == 'all'

    @conversations = @conversations.where(status: params[:status] || DEFAULT_STATUS)
  end

  def filter_by_team
    return unless @team_ids.present? && @team_ids.any?

    @conversations = @conversations.where(team_id: @team_ids)
  end

  def filter_by_labels
    return unless params[:labels]

    @conversations = @conversations.tagged_with(params[:labels], any: true)
  end

  def filter_blocked_contacts
    @conversations = @conversations.joins(:contact).where(contacts: { blocked: [false, nil] })
  end

  def filter_by_source_id
    return unless params[:source_id]

    @conversations = @conversations.joins(:contact_inbox)
    @conversations = @conversations.where(contact_inboxes: { source_id: params[:source_id] })
  end

  def filter_by_date_range
    return unless params[:date_from].present? || params[:date_to].present?

    from = params[:date_from].present? ? Time.zone.parse(params[:date_from].to_s) : nil
    to = params[:date_to].present? ? Time.zone.parse(params[:date_to].to_s) : nil

    @conversations = @conversations.where('conversations.last_activity_at >= ?', from) if from
    @conversations = @conversations.where('conversations.last_activity_at <= ?', to) if to
  end

  def compute_all_counts # rubocop:disable Metrics/MethodLength
    subquery = @conversations.reselect(
      'conversations.id', 'conversations.assignee_id', 'conversations.status',
      'conversations.first_reply_created_at', 'conversations.waiting_since'
    ).distinct

    uid = sanitized_user_id
    unattended = 'sub.status = 0 AND (sub.first_reply_created_at IS NULL OR sub.waiting_since IS NOT NULL)'

    sql = <<~SQL.squish
      SELECT
        COUNT(*)::int AS all_count,
        COUNT(*) FILTER (WHERE sub.assignee_id = #{uid})::int AS mine_count,
        COUNT(*) FILTER (WHERE sub.assignee_id IS NULL)::int AS unassigned_count,
        COUNT(*) FILTER (WHERE #{unattended})::int AS unattended_all_count,
        COUNT(*) FILTER (WHERE #{unattended} AND sub.assignee_id = #{uid})::int AS unattended_mine_count,
        COUNT(*) FILTER (WHERE #{unattended} AND sub.assignee_id IS NULL)::int AS unattended_unassigned_count
      FROM (#{subquery.to_sql}) sub
    SQL

    result = Conversation.connection.select_one(sql)
    {
      all_count: result['all_count'].to_i,
      mine_count: result['mine_count'].to_i,
      unassigned_count: result['unassigned_count'].to_i,
      unattended_all_count: result['unattended_all_count'].to_i,
      unattended_mine_count: result['unattended_mine_count'].to_i,
      unattended_unassigned_count: result['unattended_unassigned_count'].to_i
    }
  end

  def sanitized_user_id
    Conversation.connection.quote(current_user.id)
  end

  def current_page
    params[:page] || 1
  end

  def per_page
    limit = (params[:limit] || ENV.fetch('CONVERSATION_RESULTS_PER_PAGE', '25')).to_i
    [limit, 100].min
  end

  def conversations_base_query
    @conversations.includes(
      :taggings, :inbox, { assignee: [:avatar_attachment, :teams] }, { contact: :avatar_attachment }, :team, :contact_inbox
    )
  end

  def fetch_conversations
    base = conversations_base_query
    sort_by, sort_order = SORT_OPTIONS[params[:sort_by]] || SORT_OPTIONS['last_activity_at_desc']

    if params[:updated_within].present?
      base = base.where('conversations.updated_at > ?', Time.zone.now - params[:updated_within].to_i.seconds)
      [base.send(sort_by, sort_order), nil]
    elsif use_keyset_pagination?(sort_by, sort_order)
      apply_keyset_and_fetch(base, sort_order)
    else
      convs = base.send(sort_by, sort_order).page(current_page).per(per_page)
      [convs, nil]
    end
  end

  def use_keyset_pagination?(sort_by, sort_order)
    sort_by == 'sort_on_last_activity_at' && sort_order == 'desc' && params[:q].blank?
  end

  def apply_keyset_and_fetch(base, _sort_order)
    cursor_data = decode_cursor(params[:cursor])

    if cursor_data
      base = base.where(
        '(conversations.last_activity_at, conversations.id) < (?, ?)',
        cursor_data[:last_activity_at],
        cursor_data[:id]
      )
    end

    convs = base.sort_on_last_activity_at(:desc).limit(per_page + 1).to_a
    has_more = convs.size > per_page
    convs = convs.first(per_page) if has_more
    last = convs.last
    next_cursor = has_more && last ? encode_cursor(last.last_activity_at, last.id) : nil

    [convs, next_cursor]
  end

  def decode_cursor(cursor_str)
    return nil if cursor_str.blank?

    json = Base64.decode64(cursor_str)
    data = JSON.parse(json).with_indifferent_access
    {
      last_activity_at: Time.zone.parse(data[:last_activity_at].to_s),
      id: data[:id].to_i
    }
  rescue ArgumentError, JSON::ParserError
    nil
  end

  def encode_cursor(last_activity_at, id)
    Base64.strict_encode64({ last_activity_at: last_activity_at.iso8601(3), id: id }.to_json)
  end
end
ConversationFinder.prepend_mod_with('ConversationFinder')
