# Video .MOV (camera do iPhone) enviado pelo atendente vira .mp4 antes de chegar ao cliente
# (Attachments::Mp4ConversionJob). Enquanto `aguardando_mp4?` for verdade, o envio espera; a falha
# da conversao ou o limite de espera liberam o arquivo original.
module AttachmentMp4Conversion
  extend ActiveSupport::Concern

  MP4_WAIT_LIMIT = 10.minutes

  included do
    after_create_commit :schedule_mp4_conversion
  end

  def aguardando_mp4?
    mov_enviado? && meta&.dig('mp4') != 'falhou' && created_at > MP4_WAIT_LIMIT.ago
  end

  private

  # Pelo tipo que o ActiveStorage identifica nos bytes, e nao pelo `file_type`: navegador que nao conhece
  # .MOV manda o arquivo sem tipo, e ele entra como :file.
  def mov_enviado?
    message&.outgoing? && file.attached? && file.blob.content_type == 'video/quicktime'
  end

  def schedule_mp4_conversion
    return unless aguardando_mp4?

    Attachments::Mp4ConversionJob.set(wait: 2.seconds).perform_later(id)
  rescue StandardError => e
    Rails.logger.warn("[Attachment#schedule_mp4_conversion] #{e.class}: #{e.message}")
  end
end
