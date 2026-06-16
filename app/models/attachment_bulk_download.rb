# == Schema Information
#
# Table name: attachment_bulk_downloads
#
#  id                 :bigint           not null, primary key
#  account_id         :bigint           not null
#  requester_user_id  :bigint
#  conversation_id    :bigint
#  status             :integer          default(0), not null
#  params             :jsonb            not null
#  audit_meta         :jsonb            not null
#  total_count        :integer          default(0)
#  processed_count    :integer          default(0)
#  skipped_count      :integer          default(0)
#  total_bytes        :bigint           default(0)
#  file_size          :bigint
#  error_message      :text
#  started_at         :datetime
#  completed_at       :datetime
#  expires_at         :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Pedido de download em massa de mídias (galeria ou conversa). Gera um único
# .zip de forma assíncrona via Attachments::BulkDownloadJob. Espelha o padrão
# de ConversationPdfExport / ReportPdfExport (export assíncrono + polling).
class AttachmentBulkDownload < ApplicationRecord
  belongs_to :account
  belongs_to :requester_user, class_name: 'User', optional: true
  belongs_to :conversation, optional: true
  has_one_attached :file

  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

  # Limites por solicitação (decisões §14). Constantes no model; override por ENV
  # opcional no futuro, sem ENV obrigatória hoje.
  MAX_FILES       = 500
  MAX_TOTAL_BYTES = 2.gigabytes
  RETENTION       = 7.days
  # TTL da URL assinada = janela de retenção: o blob existe por 7 dias, então a
  # URL entregue ao navegador deve valer o mesmo período (regenerada a cada poll).
  DOWNLOAD_URL_TTL = 7.days

  validates :account_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %i[pending processing]) }
  scope :expired, -> { where('expires_at < ?', Time.current) }

  def download_url(expires_in: DOWNLOAD_URL_TTL)
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
