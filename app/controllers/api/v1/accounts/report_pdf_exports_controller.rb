class Api::V1::Accounts::ReportPdfExportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    export = Current.account.report_pdf_exports.find(params[:id])
    render json: serialize(export)
  end

  def create
    export = Current.account.report_pdf_exports.create!(
      report_type: params.require(:report_type),
      requester_user: Current.user,
      filters: filter_params.to_h,
      audit_meta: audit_metadata,
      expires_at: 30.days.from_now
    )
    Reports::PdfExportJob.perform_later(export.id)
    render json: serialize(export), status: :accepted
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def filter_params
    params.permit(:since, :until, :inbox_id, :team_id, :status, :business_hours, :rating,
                  :assigned_agent_id, :sla_policy_id, :label_list, :funnel_id, user_ids: [])
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
      report_type: export.report_type,
      status: export.status,
      sha256: export.sha256,
      file_size: export.file_size,
      error_message: export.error_message,
      download_url: export.completed? ? export.download_url : nil
    }
  end
end
