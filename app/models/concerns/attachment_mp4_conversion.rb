# Video .MOV (camera do iPhone) vira .mp4 (Attachments::Mp4ConversionJob), enviado pelo atendente ou recebido
# do cliente: o navegador e o app desktop so tocam .mp4. No envio, enquanto `aguardando_mp4?` for verdade, a
# mensagem espera para sair ja convertida; a falha da conversao ou o limite de espera liberam o arquivo original.
module AttachmentMp4Conversion
  extend ActiveSupport::Concern

  MP4_WAIT_LIMIT = 10.minutes

  included do
    after_create_commit :schedule_mp4_conversion
  end

  def converter_mp4?
    mov? && meta&.dig('mp4') != 'falhou' && created_at > MP4_WAIT_LIMIT.ago
  end

  # So o envio espera: o video recebido ja chegou, e so a tela troca para o .mp4 quando a conversao termina.
  def aguardando_mp4?
    message&.outgoing? && converter_mp4?
  end

  private

  # Pelo tipo que o ActiveStorage identifica nos bytes, e nao pelo `file_type`: navegador que nao conhece
  # .MOV manda o arquivo sem tipo, e ele entra como :file.
  def mov?
    file.attached? && file.blob.content_type == 'video/quicktime'
  end

  def schedule_mp4_conversion
    return unless converter_mp4?

    Attachments::Mp4ConversionJob.set(wait: 2.seconds).perform_later(id)
  rescue StandardError => e
    Rails.logger.warn("[Attachment#schedule_mp4_conversion] #{e.class}: #{e.message}")
  end
end
