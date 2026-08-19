# frozen_string_literal: true

class Conversations::ListPreloader
  Result = Struct.new(:unread_counts, :last_messages, :last_non_activity_messages, keyword_init: true)

  def self.call(conversations, user: Current.user)
    new(conversations, user).call
  end

  def initialize(conversations, user = Current.user)
    @conversations = conversations.to_a
    @conversation_ids = @conversations.map(&:id)
    @user = user
  end

  def call
    last_messages, last_non_activity_messages = batch_last_messages_combined
    Result.new(
      unread_counts: batch_unread_counts,
      last_messages: last_messages,
      last_non_activity_messages: last_non_activity_messages
    )
  end

  private

  def batch_unread_counts
    return {} if @conversation_ids.empty?

    sql = <<~SQL.squish
      SELECT c.id AS conversation_id, COUNT(m.id)::int AS cnt
      FROM conversations c
      LEFT JOIN messages m ON m.conversation_id = c.id
        AND m.account_id = c.account_id
        AND m.message_type = 0
        AND (c.team_id IS NULL OR m.team_id IS NULL OR m.team_id = c.team_id)
        AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
      WHERE c.id IN (?)
      GROUP BY c.id
    SQL
    rows = Conversation.connection.select_all(
      Conversation.sanitize_sql_array([sql, @conversation_ids])
    )
    rows.to_a.each_with_object({}) do |row, h|
      cnt = row['cnt'].to_i
      h[row['conversation_id'].to_i] = [cnt, 10].min
    end
  end

  def batch_last_messages_combined
    return [{}, {}] if @conversation_ids.empty?

    rows = fetch_combined_last_message_rows
    return [{}, {}] if rows.empty?

    build_message_maps(rows)
  end

  # ID do agente p/ isolamento (nil = admin/sem User → sem filtro). Memoizado.
  def agent_filter_id
    return @agent_filter_id if defined?(@agent_filter_id)

    @agent_filter_id = AgentMessageIsolation.viewer_restriction_id(@user, @conversations.first&.account_id)
  end

  # Times supervisionados (D2): nas conversas desses times o supervisor vê a última
  # mensagem REAL, sem o filtro por agente. Vazio para quem não supervisiona nada.
  def supervised_team_ids
    return @supervised_team_ids if defined?(@supervised_team_ids)

    @supervised_team_ids = TeamSupervision.team_ids(@user, @conversations.first&.account_id)
  end

  # Caixas em que este usuário é EXCEÇÃO do isolamento por agente: ali ele vê a última
  # mensagem REAL, de qualquer agente. Vazio para quem não é exceção em lugar nenhum, e
  # então a cláusula some da SQL — a query fica idêntica à de antes.
  def exempt_inbox_ids
    return @exempt_inbox_ids if defined?(@exempt_inbox_ids)

    @exempt_inbox_ids = AgentMessageIsolation.exempt_inbox_ids(@user, @conversations.first&.account_id)
  end

  # Idem para o isolamento por TIME. A cláusula de time desta query é o espelho da que
  # vive na association conversation.messages, então a exceção precisa valer aqui também —
  # senão o agente isento abriria a conversa e veria tudo, mas a PRÉVIA da lista continuaria
  # recortada. Vazio para quem não é exceção → cláusula ausente → SQL igual à de antes.
  def team_exempt_inbox_ids
    return @team_exempt_inbox_ids if defined?(@team_exempt_inbox_ids)

    account_id = @conversations.first&.account_id
    @team_exempt_inbox_ids = if @user.is_a?(User) && account_id.present?
                               @user.isolation_exempt_inbox_ids_for(account_id, TeamMessageIsolation::ISOLATION_TYPE)
                             else
                               []
                             end
  end

  # Espelho da cláusula de time da association conversation.messages: a prévia mostra a
  # mensagem do time da conversa (ou sem time). Quem for exceção do isolamento por time
  # naquela caixa sai do recorte; sem exceção nenhuma a cláusula é a mesma de sempre.
  def team_message_clause
    base = 'AND (c.team_id IS NULL OR m.team_id IS NULL OR m.team_id = c.team_id'
    return "#{base})" if team_exempt_inbox_ids.empty?

    "#{base} OR c.inbox_id IN (:team_exempt))"
  end

  # Filtra a última mensagem por agente SÓ nos inboxes com a flag ON (a lista mistura
  # inboxes). `c.team_id IN (:supervised)` é a isenção do supervisor e `c.inbox_id IN
  # (:exempt)` é a exceção por caixa — as duas somem quando não há supervisão/exceção.
  def agent_message_clause
    return '' if agent_filter_id.nil?

    supervised_or = supervised_team_ids.any? ? ' OR c.team_id IN (:supervised)' : ''
    exempt_or = exempt_inbox_ids.any? ? ' OR c.inbox_id IN (:exempt)' : ''
    'AND (i.agent_message_isolation IS NOT TRUE OR m.agent_id IS NULL ' \
      "OR m.agent_id = :uid#{supervised_or}#{exempt_or})"
  end

  def last_message_binds
    binds = { ids: @conversation_ids }
    binds[:uid] = agent_filter_id if agent_filter_id
    binds[:supervised] = supervised_team_ids if agent_filter_id && supervised_team_ids.any?
    binds[:exempt] = exempt_inbox_ids if agent_filter_id && exempt_inbox_ids.any?
    binds[:team_exempt] = team_exempt_inbox_ids if team_exempt_inbox_ids.any?
    binds
  end

  def fetch_combined_last_message_rows # rubocop:disable Metrics/MethodLength
    inbox_join = agent_filter_id ? 'INNER JOIN inboxes i ON i.id = c.inbox_id' : ''
    agent_where = agent_message_clause
    team_where = team_message_clause

    sql = <<~SQL.squish
      WITH last_all AS (
        SELECT DISTINCT ON (m.conversation_id) m.id, m.conversation_id
        FROM messages m
        INNER JOIN conversations c ON c.id = m.conversation_id
        #{inbox_join}
        WHERE m.conversation_id IN (:ids)
          AND m.account_id = c.account_id
          #{team_where}
          #{agent_where}
        ORDER BY m.conversation_id, m.created_at DESC, m.id DESC
      ),
      last_non_activity AS (
        SELECT DISTINCT ON (m.conversation_id) m.id, m.conversation_id
        FROM messages m
        INNER JOIN conversations c ON c.id = m.conversation_id
        #{inbox_join}
        WHERE m.conversation_id IN (:ids)
          AND m.account_id = c.account_id
          AND m.message_type != 2
          #{team_where}
          #{agent_where}
        ORDER BY m.conversation_id, m.id DESC
      )
      SELECT 'all' AS kind, id, conversation_id FROM last_all
      UNION ALL
      SELECT 'non_activity' AS kind, id, conversation_id FROM last_non_activity
    SQL

    Conversation.connection.select_all(
      Conversation.sanitize_sql_array([sql, last_message_binds])
    ).to_a
  end

  def build_message_maps(rows)
    msg_ids = rows.map { |r| r['id'].to_i }.uniq
    messages_by_id = Message.where(id: msg_ids)
                            .includes([{ attachments: [{ file_attachment: [:blob] }] }])
                            .index_by(&:id)

    last_messages = {}
    last_non_activity = {}

    rows.each do |row|
      msg = messages_by_id[row['id'].to_i]
      next unless msg

      conv_id = row['conversation_id'].to_i
      if row['kind'] == 'all'
        last_messages[conv_id] = msg
      else
        last_non_activity[conv_id] = msg
      end
    end

    [last_messages, last_non_activity]
  end
end
