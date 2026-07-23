# Constrói os escopos de visibilidade da Galeria de forma reutilizável fora do
# controller (usado pelo AttachmentsController#index/#links E pelo fluxo de
# bulk download). Recebe user/account/filters explicitamente — NUNCA depende de
# `Current` (thread-local), pois também roda dentro de um job Sidekiq.
#
# Regra de ouro: o usuário só enxerga (e baixa) anexos de inboxes às quais está
# atribuído, e mídia incoming de canais WhatsApp fica escondida na galeria.
class Attachments::GalleryScopeBuilder
  ALLOWED_TYPES = %w[image video file audio ig_reel].freeze
  DEFAULT_TYPES = %w[image video].freeze

  # Canais cuja origem de mídia é uma integração externa (WhatsApp via WAHA/Cloud API).
  # Esconde TODAS as mídias INCOMING (do contato) desses canais. Mantém:
  # - Outgoing em qualquer canal (mídia que o time enviou)
  # - Incoming em canais não-WhatsApp (web widget, email, etc.)
  WHATSAPP_INTEGRATION_CHANNELS = %w[Channel::Api Channel::Whatsapp].freeze

  def initialize(user:, account:, filters: {})
    @user = user
    @account = account
    @filters = (filters || {}).with_indifferent_access
  end

  # Escopo de anexos SEM filtro de tipo nem dedup. Aplica visibilidade +
  # regra WhatsApp + filtros de inbox/contato/data/busca. Base para o modo
  # "ids" do bulk download (ids ∩ visibilidade).
  def base_scope
    inbox_ids = visible_inbox_ids
    return Attachment.none if inbox_ids.blank?

    scope = Attachment.joins(message: { conversation: :inbox })
                      .where(messages: { account_id: @account.id })
                      .where(conversations: { inbox_id: inbox_ids })
    scope = exclude_incoming_whatsapp(scope)
    scope = exclude_isolated_conversations(scope)
    scope = filter_by_inbox(scope)
    scope = filter_by_contact(scope)
    scope = filter_by_date_range(scope)
    filter_by_query(scope)
  end

  # Escopo dedupado e filtrado por tipo — exatamente o conjunto que a galeria
  # exibe na aba atual. Usado pelo index e pelo "selecionar todos do filtro".
  def deduped_scope(types: nil)
    # Sem inboxes visíveis (ex.: requester removido) base_scope é Attachment.none,
    # que NÃO junta `messages` — a janela de dedup referencia messages.sender_id e
    # estouraria PG::UndefinedTable. Curto-circuita p/ escopo vazio.
    return Attachment.none if visible_inbox_ids.blank?

    base = base_scope.where(file_type: types.presence || requested_types)
    inner_sql = base
                .joins('JOIN active_storage_attachments asa ON asa.record_id = attachments.id ' \
                       "AND asa.record_type = 'Attachment' AND asa.name = 'file'")
                .joins('JOIN active_storage_blobs asb ON asb.id = asa.blob_id')
                .select(Arel.sql(<<~SQL.squish))
                  attachments.*,
                  ROW_NUMBER() OVER (
                    PARTITION BY asb.byte_size, asb.filename, messages.sender_id, messages.sender_type,
                                 date_trunc('hour', attachments.created_at)
                    ORDER BY attachments.created_at DESC
                  ) AS dedup_rn
                SQL
                .to_sql

    Attachment.from(Arel.sql("(#{inner_sql}) AS attachments")).where('dedup_rn = 1')
  end

  def links_scope
    inbox_ids = visible_inbox_ids
    return Message.none if inbox_ids.blank?

    # ILIKE com '://' aproveita índice GIN pg_trgm em messages.content (>= 3 chars).
    scope = @account.messages
                    .where("content ILIKE '%://%'")
                    .joins(conversation: :inbox)
                    .where(conversations: { inbox_id: inbox_ids })
    scope = exclude_isolated_conversations(scope)
    scope = filter_inbox(scope)
    scope = filter_contact(scope)
    scope = filter_message_date_range(scope)
    filter_message_query(scope)
  end

  def requested_types
    requested = (@filters[:type].presence || DEFAULT_TYPES.join(',')).split(',').map(&:strip)
    types = requested & ALLOWED_TYPES
    types.presence || DEFAULT_TYPES
  end

  # Inboxes visíveis ao usuário NESTA conta. Self-contained (não usa
  # User#assigned_inboxes, que depende de Current.account e quebraria no job):
  # admin vê todas as inboxes da conta; agente vê só as que é membro.
  def visible_inbox_ids
    # requester_user é optional (pode ter sido removido entre o pedido e o job):
    # sem usuário não há visibilidade -> escopo vazio (job falha graciosamente).
    return [] if @user.blank?

    @visible_inbox_ids ||= if account_administrator?
                             @account.inboxes.pluck(:id)
                           else
                             @user.inboxes.where(account_id: @account.id).pluck(:id)
                           end
  end

  private

  def account_administrator?
    @account.account_users.exists?(user_id: @user.id, role: :administrator)
  end

  def exclude_incoming_whatsapp(scope)
    scope.where(
      'messages.message_type = :outgoing OR inboxes.channel_type NOT IN (:wa)',
      outgoing: 1,
      wa: WHATSAPP_INTEGRATION_CHANNELS
    )
  end

  # Num inbox com isolamento por agente ligado, esconde da galeria a mídia/link das
  # conversas atribuídas a OUTRO agente — a superfície de conta não passa pelo guard
  # por-conversa (AgentConversationAccessConcern), então o vazamento é fechado aqui.
  def exclude_isolated_conversations(scope)
    AgentConversationIsolation.exclude_hidden(scope, @user, @account)
  end

  # --- filtros compartilhados entre attachments e links -------------------
  # (consolidados: a versão de attachments filtra por conversations.inbox_id /
  # attachments.created_at; a de links filtra messages.created_at — a única
  # diferença é a coluna de data, parametrizada em apply_date_range)

  def filter_by_inbox(scope)
    return scope if @filters[:inbox_id].blank?

    scope.where(conversations: { inbox_id: @filters[:inbox_id] })
  end
  alias filter_inbox filter_by_inbox

  def filter_by_contact(scope)
    return scope if @filters[:contact_id].blank?

    scope.where(conversations: { contact_id: @filters[:contact_id] })
  end
  alias filter_contact filter_by_contact

  def filter_by_date_range(scope)
    apply_date_range(scope, 'attachments.created_at')
  end

  def filter_message_date_range(scope)
    apply_date_range(scope, 'messages.created_at')
  end

  def apply_date_range(scope, column)
    # Data malformada -> parse_time devolve nil. Aplicar `col >= NULL` zeraria a
    # galeria silenciosamente (§T5); preferimos IGNORAR o filtro inválido —
    # comportamento tolerante padrão de listagem (não quebra links/bookmarks).
    after = parse_time(@filters[:after]) if @filters[:after].present?
    before = parse_time(@filters[:before]) if @filters[:before].present?
    scope = scope.where("#{column} >= ?", after) if after
    scope = scope.where("#{column} <= ?", before) if before
    scope
  end

  def filter_by_query(scope)
    return scope if @filters[:q].blank?

    scope.joins(message: { conversation: :contact })
         .where('messages.content ILIKE :q OR contacts.name ILIKE :q', q: query_term)
  end

  def filter_message_query(scope)
    return scope if @filters[:q].blank?

    scope.joins(conversation: :contact)
         .where('messages.content ILIKE :q OR contacts.name ILIKE :q', q: query_term)
  end

  def query_term
    "%#{@filters[:q].to_s.strip}%"
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
