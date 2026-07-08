# == Schema Information
#
# Table name: report_pdf_exports
#
#  id                :bigint           not null, primary key
#  account_id        :bigint           not null
#  requester_user_id :bigint
#  report_type       :string           not null
#  status            :integer          default(0), not null
#  filters           :jsonb            not null
#  audit_meta        :jsonb            not null
#  sha256            :string(64)
#  file_size         :bigint
#  started_at        :datetime
#  completed_at      :datetime
#  expires_at        :datetime
#  error_message     :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class ReportPdfExport < ApplicationRecord
  # Relatorios exportaveis como PDF brandeado ChatSPX. Espelha ConversationPdfExport,
  # mas generico: o report_type seleciona o template/resolver de dados.
  SUPPORTED_REPORT_TYPES = %w[nps csat bot conversations overview agent inbox team label sla funnel agent_assignment].freeze

  belongs_to :account
  belongs_to :requester_user, class_name: 'User', optional: true
  has_one_attached :file

  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :report_type, presence: true, inclusion: { in: SUPPORTED_REPORT_TYPES }

  scope :recent, -> { order(created_at: :desc) }

  def download_url(expires_in: 24.hours)
    return nil unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_url(
      file,
      host: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
      expires_in: expires_in,
      disposition: 'attachment'
    )
  end

  def duration_ms
    return nil unless started_at && completed_at

    ((completed_at - started_at) * 1000).round
  end
end
