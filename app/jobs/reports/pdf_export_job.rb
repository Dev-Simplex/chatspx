class Reports::PdfExportJob < ApplicationJob
  queue_as :low

  discard_on ActiveJob::DeserializationError

  def perform(export_id)
    export = ReportPdfExport.find_by(id: export_id)
    return unless export

    export.update!(status: :processing, started_at: Time.current)
    result = Reports::PdfExportService.new(export: export).call
    attach_and_complete(export, result)
  rescue StandardError => e
    Rails.logger.error("[report_pdf_export] erro export #{export_id}: #{e.class} - #{e.message}\n#{e.backtrace.first(8).join("\n")}")
    export&.update(status: :failed, error_message: "#{e.class}: #{e.message}".truncate(2000), completed_at: Time.current)
    raise
  end

  private

  def attach_and_complete(export, result)
    filename = "#{export.report_type}_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.pdf"
    export.file.attach(
      io: StringIO.new(result.bytes),
      filename: filename,
      content_type: 'application/pdf'
    )
    export.update!(
      status: :completed,
      sha256: result.sha256,
      file_size: result.bytes.bytesize,
      completed_at: Time.current
    )
  end
end
