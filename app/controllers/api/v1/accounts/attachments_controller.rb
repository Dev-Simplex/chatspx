class Api::V1::Accounts::AttachmentsController < Api::V1::Accounts::BaseController
  ALLOWED_TYPES = %w[image video file audio ig_reel].freeze
  RESULTS_PER_PAGE = 30
  CACHE_EXPIRES_IN = 5.minutes
  CACHE_VERSION = 'v2'

  # Canais cuja origem de mídia é uma integração externa (WhatsApp via WAHA/Cloud API).
  # Esconde TODAS as mídias INCOMING (do contato) desses canais. Mantém:
  # - Outgoing em qualquer canal (mídia que o time enviou)
  # - Incoming em canais não-WhatsApp (web widget, email, etc.)
  WHATSAPP_INTEGRATION_CHANNELS = %w[Channel::Api Channel::Whatsapp].freeze

  before_action :ensure_user

  def index
    cached = Rails.cache.fetch(attachments_cache_key, expires_in: CACHE_EXPIRES_IN) do
      result = deduped_attachments_scope
               .reorder(sort_clause)
               .page(page_param).per(RESULTS_PER_PAGE)
      {
        ids: result.pluck(:id),
        total_count: result.total_count,
        current_page: result.current_page,
        total_pages: result.total_pages
      }
    end

    @attachments_count = cached[:total_count]
    @current_page = cached[:current_page]
    @total_pages = cached[:total_pages]
    @attachments = Attachment.where(id: cached[:ids])
                             .includes(
                               { file_attachment: [:blob] },
                               { message: [{ sender: { avatar_attachment: [:blob] } }, :conversation] }
                             )
                             .reorder(sort_clause)
    set_cache_control_headers
  end

  def links
    cached = Rails.cache.fetch(links_cache_key, expires_in: CACHE_EXPIRES_IN) do
      result = links_scope.reorder(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
      {
        ids: result.pluck(:id),
        total_count: result.total_count,
        current_page: result.current_page,
        total_pages: result.total_pages
      }
    end

    @messages_count = cached[:total_count]
    @current_page = cached[:current_page]
    @total_pages = cached[:total_pages]
    @messages = Message.where(id: cached[:ids])
                       .includes(:conversation, { sender: { avatar_attachment: [:blob] } })
                       .reorder(created_at: :desc)
    set_cache_control_headers
  end

  private

  def ensure_user
    render json: { error: 'unauthorized' }, status: :unauthorized and return if Current.user.blank?
  end

  def set_cache_control_headers
    response.cache_control[:private] = true
    response.cache_control[:max_age] = 60
  end

  def attachments_cache_key
    ['gallery_attachments', CACHE_VERSION, Current.account.id, Current.user.id,
     filter_token, page_param].join(':')
  end

  def links_cache_key
    ['gallery_links', CACHE_VERSION, Current.account.id, Current.user.id,
     filter_token, page_param].join(':')
  end

  def filter_token
    [params[:type], params[:inbox_id], params[:contact_id],
     params[:after], params[:before], params[:q], params[:sort]].map(&:to_s).join('|')
  end

  def requested_types
    requested = (params[:type].presence || 'image,video').split(',').map(&:strip)
    types = requested & ALLOWED_TYPES
    types.presence || %w[image video]
  end

  def base_scope
    inbox_ids = visible_inbox_ids
    return Attachment.none if inbox_ids.blank?

    scope = Attachment.joins(message: { conversation: :inbox })
                      .where(messages: { account_id: Current.account.id })
                      .where(conversations: { inbox_id: inbox_ids })
    scope = exclude_incoming_whatsapp(scope)
    scope = filter_by_inbox(scope)
    scope = filter_by_contact(scope)
    scope = filter_by_date_range(scope)
    filter_by_query(scope)
  end

  # Esconde mídias incoming (do contato) em canais WhatsApp.
  # Mantém:
  # - Outgoing em qualquer canal (mídia que o time enviou)
  # - Incoming em canais não-WhatsApp (web widget, email, etc.)
  def exclude_incoming_whatsapp(scope)
    scope.where(
      'messages.message_type = :outgoing OR inboxes.channel_type NOT IN (:wa)',
      outgoing: 1,
      wa: WHATSAPP_INTEGRATION_CHANNELS
    )
  end

  # Deduplica anexos repetidos: mesmo blob (filename + byte_size) enviado pelo mesmo sender
  # dentro da mesma hora. Mantém o mais recente.
  # Window function ROW_NUMBER PARTITION evita materializar todos os IDs em memória.
  def deduped_attachments_scope
    base = base_scope.where(file_type: requested_types)
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
    scope = Current.account.messages
                   .where("content ILIKE '%://%'")
                   .joins(conversation: :inbox)
                   .where(conversations: { inbox_id: inbox_ids })
    scope = filter_messages_by_inbox(scope)
    scope = filter_messages_by_contact(scope)
    scope = filter_messages_by_date_range(scope)
    filter_messages_by_query(scope)
  end

  def visible_inbox_ids
    Current.user.assigned_inboxes.pluck(:id)
  end

  def filter_by_inbox(scope)
    return scope if params[:inbox_id].blank?

    scope.where(conversations: { inbox_id: params[:inbox_id] })
  end

  def filter_by_contact(scope)
    return scope if params[:contact_id].blank?

    scope.where(conversations: { contact_id: params[:contact_id] })
  end

  def filter_by_date_range(scope)
    scope = scope.where('attachments.created_at >= ?', parse_time(params[:after])) if params[:after].present?
    scope = scope.where('attachments.created_at <= ?', parse_time(params[:before])) if params[:before].present?
    scope
  end

  def filter_by_query(scope)
    return scope if params[:q].blank?

    term = "%#{params[:q].to_s.strip}%"
    scope.joins(message: { conversation: :contact })
         .where(
           'messages.content ILIKE :q OR contacts.name ILIKE :q',
           q: term
         )
  end

  def filter_messages_by_inbox(scope)
    return scope if params[:inbox_id].blank?

    scope.where(conversations: { inbox_id: params[:inbox_id] })
  end

  def filter_messages_by_contact(scope)
    return scope if params[:contact_id].blank?

    scope.where(conversations: { contact_id: params[:contact_id] })
  end

  def filter_messages_by_date_range(scope)
    scope = scope.where('messages.created_at >= ?', parse_time(params[:after])) if params[:after].present?
    scope = scope.where('messages.created_at <= ?', parse_time(params[:before])) if params[:before].present?
    scope
  end

  def filter_messages_by_query(scope)
    return scope if params[:q].blank?

    term = "%#{params[:q].to_s.strip}%"
    scope.joins(conversation: :contact)
         .where('messages.content ILIKE :q OR contacts.name ILIKE :q', q: term)
  end

  def sort_clause
    case params[:sort]
    when 'date_asc' then 'attachments.created_at ASC'
    else 'attachments.created_at DESC'
    end
  end

  def page_param
    page = params[:page].to_i
    page.positive? ? page : 1
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
