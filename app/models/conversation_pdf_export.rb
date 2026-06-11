# == Schema Information
#
# Table name: conversation_pdf_exports
#
#  id                 :bigint           not null, primary key
#  conversation_id    :bigint           not null
#  account_id         :bigint           not null
#  requester_user_id  :bigint
#  status             :integer          default(0), not null
#  filters            :jsonb            not null
#  audit_meta         :jsonb            not null
#  sha256             :string(64)
#  file_size          :bigint
#  bates_count        :integer
#  timestamp_token    :binary
#  started_at         :datetime
#  completed_at       :datetime
#  expires_at         :datetime
#  error_message      :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class ConversationPdfExport < ApplicationRecord
  belongs_to :conversation
  belongs_to :account
  belongs_to :requester_user, class_name: 'User', optional: true
  has_one_attached :file

  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :conversation_id, :account_id, presence: true
  validates :filters, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_conversation, ->(conv_id) { where(conversation_id: conv_id) }

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
