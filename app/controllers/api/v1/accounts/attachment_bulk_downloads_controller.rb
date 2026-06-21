class Api::V1::Accounts::AttachmentBulkDownloadsController < Api::V1::Accounts::BaseController
  before_action :ensure_user

  # Polling do front. Restrito ao requester (ou admin) — nunca expõe export alheio.
  def show
    bulk = Current.account.attachment_bulk_downloads.find(params[:id])
    authorize_owner!(bulk)
    render json: serialize(bulk)
  end

  # Dois modos mutuamente exclusivos:
  #   { attachment_ids: [...] }                        -> seleção manual
  #   { filters: {...} } (+ conversation_id opcional)  -> "tudo do filtro" / "todas da conversa"
  def create
    conversation = resolve_and_authorize_conversation

    resolver = Attachments::BulkDownloadScopeResolver.new(
      account: Current.account,
      user: Current.user,
      conversation_id: conversation&.id,
      attachment_ids: params[:attachment_ids],
      filters: filter_params.to_h
    )

    error = validate_request(resolver)
    return render json: error[:body], status: error[:status] if error

    bulk = build_record(conversation, resolver.count)
    Attachments::BulkDownloadJob.perform_later(bulk.id)
    render json: serialize(bulk), status: :accepted
  end

  private

  def ensure_user
    render json: { error: 'unauthorized' }, status: :unauthorized and return if Current.user.blank?
  end

  # conversation_id chega como display_id (igual ao resto da API de conversa).
  def resolve_and_authorize_conversation
    return if params[:conversation_id].blank?

    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    conversation
  end

  def validate_request(resolver)
    count = resolver.count
    return { body: { error: 'nothing_to_download' }, status: :unprocessable_entity } if count.zero?

    if count > AttachmentBulkDownload::MAX_FILES
      return { body: { error: 'too_many_files', limit: AttachmentBulkDownload::MAX_FILES, requested: count },
               status: :unprocessable_entity }
    end

    if resolver.total_bytes > AttachmentBulkDownload::MAX_TOTAL_BYTES
      return { body: { error: 'too_large', limit: AttachmentBulkDownload::MAX_TOTAL_BYTES, requested: resolver.total_bytes },
               status: :unprocessable_entity }
    end

    return { body: { error: 'export_active' }, status: :too_many_requests } if active_export?

    nil
  end

  # Anti-abuso: no máximo 1 export ativo (pending/processing) por usuário.
  def active_export?
    Current.account.attachment_bulk_downloads
           .active
           .exists?(requester_user_id: Current.user.id)
  end

  def build_record(conversation, count)
    Current.account.attachment_bulk_downloads.create!(
      requester_user: Current.user,
      conversation_id: conversation&.id,
      status: :pending,
      params: persisted_params(conversation),
      audit_meta: audit_metadata(conversation),
      total_count: count,
      expires_at: AttachmentBulkDownload::RETENTION.from_now
    )
  end

  def persisted_params(conversation)
    {
      attachment_ids: Array(params[:attachment_ids]).map(&:to_i).reject(&:zero?).presence,
      filters: filter_params.to_h.presence,
      conversation_id: conversation&.id
    }.compact
  end

  def filter_params
    params.fetch(:filters, {}).permit(:type, :inbox_id, :contact_id, :before, :after, :q)
  end

  def audit_metadata(conversation)
    {
      requester_user_id: Current.user&.id,
      requester_name: Current.user&.name,
      requester_email: Current.user&.email,
      ip: request.remote_ip,
      user_agent: request.user_agent&.truncate(500),
      origin: conversation ? 'conversation' : 'gallery'
    }
  end

  def authorize_owner!(bulk)
    return if bulk.requester_user_id == Current.user.id
    return if Current.account_user&.administrator?

    raise Pundit::NotAuthorizedError
  end

  def serialize(bulk)
    {
      id: bulk.id,
      status: bulk.status,
      total_count: bulk.total_count,
      processed_count: bulk.processed_count,
      skipped_count: bulk.skipped_count,
      file_size: bulk.file_size,
      error_message: bulk.error_message,
      download_url: bulk.completed? ? bulk.download_url : nil
    }
  end
end
