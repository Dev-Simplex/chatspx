# Previa de video (primeiro quadro), gerada no servidor por Attachments::VideoPosterJob e servida como `thumb_url`.
module AttachmentVideoPoster
  extend ActiveSupport::Concern

  included do
    has_one_attached :poster
    after_create_commit :schedule_video_poster
  end

  private

  def video_poster_url
    poster.attached? ? url_for(poster) : ''
  end

  def schedule_video_poster
    # O .MOV ganha a previa quando a conversao termina, ja do .mp4 (AttachmentMp4Conversion).
    return unless video? && file.attached? && !converter_mp4?

    Attachments::VideoPosterJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.warn("[Attachment#schedule_video_poster] #{e.class}: #{e.message}")
  end
end
