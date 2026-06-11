class Api::V2::Accounts::Conversations::PdfExportsController < Api::V1::Accounts::BaseController
  before_action :conversation

  def show
    export = ConversationPdfExport.find_by!(id: params[:id], conversation_id: @conversation.id)
    render json: serialize(export)
  end

  def create
    export = build_export
    Conversations::ExportPdfJob.perform_later(export.id)
    render json: serialize(export), status: :accepted
  end

  private

  def conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def build_export
    ConversationPdfExport.create!(
      conversation: @conversation,
      account: Current.account,
      requester_user: Current.user,
      filters: permitted_filters.to_h,
      audit_meta: audit_metadata,
      expires_at: 5.years.from_now
    )
  end

  def permitted_filters
    params.require(:pdf_export).permit(
      :include_incoming,
      :include_outgoing,
      :include_private,
      :include_activity,
      :date_from,
      :date_to
    )
  end

  def audit_metadata
    {
      requester_user_id: Current.user&.id,
      requester_name: Current.user&.name,
      requester_email: Current.user&.email,
      ip: request.remote_ip,
      user_agent: request.user_agent&.truncate(500)
    }
  end

  def serialize(export)
    {
      id: export.id,
      status: export.status,
      sha256: export.sha256,
      file_size: export.file_size,
      bates_count: export.bates_count,
      started_at: export.started_at,
      completed_at: export.completed_at,
      duration_ms: export.duration_ms,
      error_message: export.error_message,
      download_url: export.completed? ? export.download_url : nil
    }
  end
end
