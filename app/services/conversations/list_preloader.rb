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
      INNER JOIN inboxes i ON i.id = c.inbox_id
      LEFT JOIN messages m ON m.conversation_id = c.id
        AND m.account_id = c.account_id
        AND m.message_type = 0
        AND #{team_isolation_where}
        AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
      WHERE c.id IN (?)
      GROUP BY c.id
    SQL
    rows = Conversation.connection.select_all(
      Conversation.sanitize_sql_array([sql, @conversation_ids])
    )
    capped_unread_counts(rows)
  end

  # A UI mostra "9+" acima de 10; o teto vive aqui para o SQL nao carregar essa regra.
  def capped_unread_counts(rows)
    rows.to_a.each_with_object({}) do |row, h|
      h[row['conversation_id'].to_i] = [row['cnt'].to_i, 10].min
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

  # Filtro por TIME da mensagem (team_message_isolation) — o espelho, na PREVIA, do que a
  # association `Conversation#messages` faz na conversa aberta.
  #
  # Era `(c.team_id IS NULL OR m.team_id IS NULL OR m.team_id = c.team_id)`, INCONDICIONAL:
  # nao olhava a flag nenhuma. Uma mensagem com team_id defasado (a conversa trocou de time
  # e o UpdateMessagesTeamIdJob ainda nao rodou) sumia da previa mesmo na caixa com o
  # isolamento DESLIGADO — e a lista mostrava uma mensagem antiga como se fosse a ultima.
  # E o mesmo bug do `messages` vs `all_messages` que derrubou em silencio o no de mensagem
  # do flow, o CSAT e o NPS (ver conversations/message_window_service.rb), aqui na previa.
  #
  # Agora exige a regra ALCANCAR a conversa: flag ligada E time no escopo. `NOT <alcanca>`
  # ja cobre a conversa SEM time (team_message_isolation esta em Inbox::TEAMLESS_EXEMPT_RULES),
  # entao o `c.team_id IS NULL` solto sai daqui.
  # O COALESCE nao e enfeite: `inboxes.team_message_isolation` e a UNICA das 3 flags que
  # ficou NULLABLE (as outras duas sao NOT NULL). Numa linha com a flag NULL, `flag = true`
  # da NULL, `NOT NULL` da NULL, e a mensagem com time defasado seria descartada em
  # silencio — justamente o bug que este metodo existe para fechar. O Ruby
  # (`isolation_applies_to_team?`) ja trata NULL como false (`unless self[key]`); aqui o SQL
  # passa a concordar com ele.
  #
  # SEGUNDO EIXO, a ISENCAO por agente: quem for excecao do isolamento por time naquela
  # caixa sai do recorte tambem aqui. A previa e o espelho da association
  # `Conversation#messages`; sem isto o agente isento abriria a conversa e veria tudo, mas
  # a PREVIA da lista continuaria recortada. Sem excecao nenhuma a clausula nao aparece e
  # a SQL fica identica a de antes.
  def team_isolation_where
    applies = Inbox.isolation_applies_sql(:team_message_isolation, inbox_alias: 'i', conversation_alias: 'c')
    "(NOT COALESCE(#{applies}, FALSE)#{isento_or('c.inbox_id', team_exempt_inbox_ids)} " \
      'OR m.team_id IS NULL OR m.team_id = c.team_id)'
  end

  # Fragmento ` OR <coluna> IN (1,2,3)`, ou vazio quando nao ha isencao.
  # Ids inteiros interpolados de proposito, e nao bind nomeado: `team_isolation_where` roda
  # tambem em `batch_unread_counts`, que usa bind POSICIONAL (`?`) — um `:nome` ali viraria
  # erro de bind. `to_i` e a barreira: sao ids vindos do banco, nunca entrada de usuario.
  def isento_or(coluna, ids)
    lista = Array(ids).map(&:to_i)
    return '' if lista.empty?

    " OR #{coluna} IN (#{lista.join(',')})"
  end

  # Caixas em que este usuario e EXCECAO do isolamento por AGENTE: ali ele ve a ultima
  # mensagem REAL, de qualquer agente.
  def exempt_inbox_ids
    return @exempt_inbox_ids if defined?(@exempt_inbox_ids)

    @exempt_inbox_ids = AgentMessageIsolation.exempt_inbox_ids(@user, @conversations.first&.account_id)
  end

  # Idem para o isolamento por TIME.
  def team_exempt_inbox_ids
    return @team_exempt_inbox_ids if defined?(@team_exempt_inbox_ids)

    account_id = @conversations.first&.account_id
    @team_exempt_inbox_ids = if @user.is_a?(User) && account_id.present?
                               @user.isolation_exempt_inbox_ids_for(account_id, TeamMessageIsolation::ISOLATION_TYPE)
                             else
                               []
                             end
  end

  def fetch_combined_last_message_rows # rubocop:disable Metrics/MethodLength
    uid = agent_filter_id
    supervised = uid ? supervised_team_ids : []
    # Filtra a última mensagem por agente SÓ nos inboxes com a flag ON (a lista mistura inboxes).
    # `c.team_id IN (:supervised)` é a isenção do supervisor — cláusula ausente quando não há supervisão.
    supervised_or = supervised.any? ? ' OR c.team_id IN (:supervised)' : ''
    # `NOT <regra alcanca>` no lugar do antigo `i.agent_message_isolation IS NOT TRUE`: a
    # previa volta a ser a mensagem REAL quando a regra nao alcanca a conversa (flag off,
    # conversa sem time, ou time fora da lista escolhida na caixa).
    applies = Inbox.isolation_applies_sql(:agent_message_isolation, inbox_alias: 'i', conversation_alias: 'c')
    # `c.inbox_id IN (...)` e a EXCECAO por caixa, o segundo eixo: clausula ausente quando
    # o usuario nao e excecao em lugar nenhum.
    exempt_or = isento_or('c.inbox_id', exempt_inbox_ids)
    agent_where = uid ? "AND (NOT #{applies} OR m.agent_id IS NULL OR m.agent_id = :uid#{supervised_or}#{exempt_or})" : ''
    # O JOIN com `inboxes` deixou de ser condicional ao `uid`: o filtro por time tambem
    # pergunta a caixa (flag + lista), entao a tabela precisa estar unida SEMPRE.
    team_where = team_isolation_where

    sql = <<~SQL.squish
      WITH last_all AS (
        SELECT DISTINCT ON (m.conversation_id) m.id, m.conversation_id
        FROM messages m
        INNER JOIN conversations c ON c.id = m.conversation_id
        INNER JOIN inboxes i ON i.id = c.inbox_id
        WHERE m.conversation_id IN (:ids)
          AND m.account_id = c.account_id
          AND #{team_where}
          #{agent_where}
        ORDER BY m.conversation_id, m.created_at DESC, m.id DESC
      ),
      last_non_activity AS (
        SELECT DISTINCT ON (m.conversation_id) m.id, m.conversation_id
        FROM messages m
        INNER JOIN conversations c ON c.id = m.conversation_id
        INNER JOIN inboxes i ON i.id = c.inbox_id
        WHERE m.conversation_id IN (:ids)
          AND m.account_id = c.account_id
          AND m.message_type != 2
          AND #{team_where}
          #{agent_where}
        ORDER BY m.conversation_id, m.id DESC
      )
      SELECT 'all' AS kind, id, conversation_id FROM last_all
      UNION ALL
      SELECT 'non_activity' AS kind, id, conversation_id FROM last_non_activity
    SQL

    binds = { ids: @conversation_ids }
    binds[:uid] = uid if uid
    binds[:supervised] = supervised if supervised.any?
    Conversation.connection.select_all(
      Conversation.sanitize_sql_array([sql, binds])
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
