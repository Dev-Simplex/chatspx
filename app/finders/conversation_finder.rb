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
    @is_admin = administrator?
    @params = params
  end

  # Single source of truth for the admin check. Prefer the already-loaded
  # Current.account_user; fall back to an explicit lookup only when the account
  # is known but Current is not populated, so admins are never wrongly treated
  # as agents. Mirrors Conversations::PermissionFilterService.
  def administrator?
    account_user = Current.account_user
    account_user ||= @current_account && AccountUser.find_by(account_id: @current_account.id, user_id: @current_user.id)
    account_user&.administrator? || false
  end

  def perform # rubocop:disable Metrics/MethodLength
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
        ai_count: counts[:ai_count],
        awaiting_count: counts[:awaiting_count],
        awaiting_closure_count: counts[:awaiting_closure_count],
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
        ai_count: counts[:ai_count],
        awaiting_count: counts[:awaiting_count],
        awaiting_closure_count: counts[:awaiting_closure_count],
        all_count: counts[:all_count],
        unattended_assigned_to_me_count: counts[:unattended_mine_count],
        unattended_unassigned_count: counts[:unattended_unassigned_count],
        unattended_all_count: counts[:unattended_all_count]
      }
    }
  end

  def perform_meta_only
    set_up

    counts = compute_all_counts
    assigned_count = counts[:all_count] - counts[:unassigned_count]

    {
      count: {
        mine_count: counts[:mine_count],
        assigned_count: assigned_count,
        unassigned_count: counts[:unassigned_count],
        ai_count: counts[:ai_count],
        awaiting_count: counts[:awaiting_count],
        awaiting_closure_count: counts[:awaiting_closure_count],
        all_count: counts[:all_count],
        unattended_assigned_to_me_count: counts[:unattended_mine_count],
        unattended_unassigned_count: counts[:unattended_unassigned_count],
        unattended_all_count: counts[:unattended_all_count]
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
    # F2: no modo fila (reply_assignment_gate ON), a aba "Aguardando atendimento"
    # (unassigned) é escopada por time para agente não-admin: ele só vê a fila dos
    # seus próprios times, ignorando qualquer team_id vindo nos params (não dá pra
    # espiar a fila de outro time). Admin vê tudo. Agente sem nenhum time mantém o
    # comportamento atual (@team_ids vazio → sem filtro de time, via short-circuit
    # de filter_by_team) — não fica trancado fora da única fila que poderia atender.
    if force_team_queue_scope?
      @team = nil
      @team_ids = scoping_team_ids
      return
    end

    parsed_team_id = Integer(params[:team_id], exception: false)

    if parsed_team_id.present? && parsed_team_id.positive?
      @team = current_account.teams.find_by(id: parsed_team_id)
      @team_ids = @team ? [@team.id] : []
    elsif !@is_admin && member_team_ids.any?
      @team = nil
      @team_ids = scoping_team_ids
    else
      @team = nil
      @team_ids = []
    end
  end

  def member_team_ids
    @member_team_ids ||= current_user.teams.pluck(:id)
  end

  # Times que ESCOPAM a lista = membro ∪ supervisionado. A supervisão só AMPLIA:
  # se o agente não é membro de nenhum time, a lista continua SEM filtro de time
  # (quem já garante o conjunto acessível é a PermissionFilterService) — do
  # contrário virar supervisor ESTREITARIA a visão dele, o oposto da feature.
  def scoping_team_ids
    return [] if member_team_ids.empty?

    TeamSupervision.accessible_team_ids(current_user, current_account)
  end

  # Força o escopo por time na fila (aba unassigned) somente quando:
  # flag reply_assignment_gate ON + tab unassigned + usuário não-admin.
  def force_team_queue_scope?
    ai_tabs_enabled? && !@is_admin && params[:assignee_type] == 'unassigned'
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

  def filter_by_assignee_type # rubocop:disable Metrics/CyclomaticComplexity
    case @assignee_type
    when 'me'
      @conversations = @conversations.assigned_to(current_user)
    when 'unassigned'
      @conversations = ai_tabs_enabled? ? @conversations.unassigned.without_captain_assignee : @conversations.unassigned
    when 'ai'
      # IA = atribuída à IA E sem marcador de fila (as que aguardam atendente vão pro tab
      # 'awaiting'; as que aguardam encerramento, pro tab 'pending_closure').
      @conversations = @conversations.assigned_to_captain
                                     .where("conversations.custom_attributes->>'aguardando_humano_desde' IS NULL")
                                     .where("conversations.custom_attributes->>'aguardando_encerramento_desde' IS NULL")
    when 'awaiting'
      # Aguardando atendimento = a IA fez handoff e segue dona, mas marcou que é hora de
      # um humano assumir. TEM dono (IA) — por isso NÃO é "não atribuída".
      @conversations = @conversations.awaiting_human
    when 'pending_closure'
      # Aguardando encerramento = conversa parada/encerrada marcada pra um humano JULGAR o
      # fecho. A IA segue dona (responde se o cliente voltar) — some da aba IA, entra aqui.
      @conversations = @conversations.awaiting_closure
    when 'assigned'
      @conversations = @conversations.assigned
    end
    @conversations
  end

  def ai_tabs_enabled?
    current_account.reply_assignment_gate_enabled?
  end

  def filter_by_conversation_type
    case @params[:conversation_type]
    when 'mention'
      @conversations = @conversations.where(id: current_account.mentions.where(user: current_user).select(:conversation_id))
    when 'participating'
      @conversations = current_user.participating_conversations.where(account_id: current_account.id)
    when 'unattended'
      @conversations = @conversations.unattended
    when 'unread'
      @conversations = @conversations.unread
    end
    @conversations
  end

  def filter_by_query
    # robustez: só busca com q String não-vazia. Clientes/FE antigos que mandam q como
    # objeto (ActionController::Parameters) caíam em sanitize_sql_like -> NoMethodError (gsub) -> 500.
    return unless params[:q].is_a?(String) && params[:q].present?

    allowed_message_types = [Message.message_types[:incoming], Message.message_types[:outgoing]]
    agent_id = AgentMessageIsolation.viewer_restriction_id(@current_user, @current_account)
    @conversations = @conversations.where(
      'EXISTS (SELECT 1 FROM messages WHERE messages.conversation_id = conversations.id ' \
      "AND messages.content ILIKE :search AND messages.message_type IN (:types) #{query_agent_clause(agent_id)})",
      search: "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%",
      types: allowed_message_types,
      agent_id: agent_id,
      supervised: query_supervised_team_ids
    )
  end

  # Isolamento por agente: não descobrir conversas só pelo conteúdo de mensagem de outro
  # agente em inbox com a flag ON (admin/sem restrição → cláusula vazia). O supervisor do
  # time da conversa é isento (D2) e acha o conteúdo de qualquer agente do time.
  def query_agent_clause(agent_id)
    return '' if agent_id.nil?

    supervised_or = query_supervised_team_ids.any? ? 'OR conversations.team_id IN (:supervised) ' : ''
    'AND (messages.agent_id IS NULL OR messages.agent_id = :agent_id ' \
      "#{supervised_or}" \
      'OR NOT EXISTS (SELECT 1 FROM inboxes WHERE inboxes.id = conversations.inbox_id ' \
      'AND inboxes.agent_message_isolation = true))'
  end

  def query_supervised_team_ids
    @query_supervised_team_ids ||= TeamSupervision.team_ids(@current_user, @current_account)
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

  def compute_all_counts # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    subquery = @conversations.reselect(
      'conversations.id', 'conversations.assignee_id', 'conversations.status',
      'conversations.first_reply_created_at', 'conversations.waiting_since',
      'conversations.assignee_agent_bot_id', 'conversations.custom_attributes'
    ).distinct

    uid = sanitized_user_id
    unattended = 'sub.status = 0 AND (sub.first_reply_created_at IS NULL OR sub.waiting_since IS NOT NULL)'

    # unassigned_count exclui conversas da IA somente com a flag ligada (DC-4);
    # ai_count = espelho captain SEM o marcador "aguardando humano" (as que aguardam
    # vão pro awaiting_count). awaiting_count = marcador presente (IA fez handoff, segue
    # dona, esperando humano assumir).
    sql = <<~SQL.squish
      SELECT
        COUNT(*)::int AS all_count,
        COUNT(*) FILTER (WHERE sub.assignee_id = #{uid})::int AS mine_count,
        COUNT(*) FILTER (WHERE sub.assignee_id IS NULL#{' AND ab.id IS NULL' if ai_tabs_enabled?})::int AS unassigned_count,
        COUNT(*) FILTER (WHERE ab.id IS NOT NULL AND (sub.custom_attributes->>'aguardando_humano_desde') IS NULL AND (sub.custom_attributes->>'aguardando_encerramento_desde') IS NULL)::int AS ai_count,
        COUNT(*) FILTER (WHERE (sub.custom_attributes->>'aguardando_humano_desde') IS NOT NULL)::int AS awaiting_count,
        COUNT(*) FILTER (WHERE (sub.custom_attributes->>'aguardando_encerramento_desde') IS NOT NULL)::int AS awaiting_closure_count,
        COUNT(*) FILTER (WHERE #{unattended})::int AS unattended_all_count,
        COUNT(*) FILTER (WHERE #{unattended} AND sub.assignee_id = #{uid})::int AS unattended_mine_count,
        COUNT(*) FILTER (WHERE #{unattended} AND sub.assignee_id IS NULL)::int AS unattended_unassigned_count
      FROM (#{subquery.to_sql}) sub
      LEFT JOIN agent_bots ab ON ab.id = sub.assignee_agent_bot_id AND ab.bot_type = 1
    SQL

    result = Conversation.connection.select_one(sql)
    {
      all_count: result['all_count'].to_i,
      mine_count: result['mine_count'].to_i,
      unassigned_count: result['unassigned_count'].to_i,
      ai_count: result['ai_count'].to_i,
      awaiting_count: result['awaiting_count'].to_i,
      awaiting_closure_count: result['awaiting_closure_count'].to_i,
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
      :taggings, :inbox, { assignee: [:avatar_attachment, :teams] }, { contact: :avatar_attachment }, :team, :contact_inbox,
      :assignee_agent_bot
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
