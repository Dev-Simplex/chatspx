class Api::V1::Accounts::AttachmentsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 30
  CACHE_EXPIRES_IN = 5.minutes
  CACHE_VERSION = 'v3'.freeze

  before_action :ensure_user

  def index
    cached = cached_attachment_page
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

  # Escopo/visibilidade/dedup vivem no GalleryScopeBuilder (reusado pelo bulk download).
  def scope_builder
    @scope_builder ||= Attachments::GalleryScopeBuilder.new(
      user: Current.user, account: Current.account, filters: gallery_filters
    )
  end

  def gallery_filters
    {
      type: params[:type], inbox_id: params[:inbox_id], contact_id: params[:contact_id],
      before: params[:before], after: params[:after], q: params[:q]
    }
  end

  def cached_attachment_page
    Rails.cache.fetch(attachments_cache_key, expires_in: CACHE_EXPIRES_IN) do
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
  end

  def deduped_attachments_scope
    scope_builder.deduped_scope
  end

  def links_scope
    scope_builder.links_scope
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
end
