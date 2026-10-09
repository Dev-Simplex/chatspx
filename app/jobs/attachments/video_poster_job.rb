# Gera a previa (primeiro quadro) de um video e grava em `Attachment#poster`; o `thumb_url` do video passa a
# apontar para ela (Video::PosterExtractor explica por que a previa nao pode ficar com o navegador).
#
# Roda depois do commit do anexo; o .MOV so entra aqui depois de virar .mp4 (Attachments::Mp4ConversionJob),
# para nao disputar a memoria do worker com a conversao.
class Attachments::VideoPosterJob < ApplicationJob
  queue_as :low
  # O upload do arquivo pode terminar depois que o job comeca (o mesmo motivo do Attachments::Mp4ConversionJob).
  retry_on ActiveStorage::FileNotFoundError, wait: 3.seconds, attempts: 5

  def perform(attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return unless attachment&.video? && attachment.file.attached? && !attachment.poster.attached?

    refresh_bubble(attachment) if attach_poster(attachment)
  end

  private

  def attach_poster(attachment)
    Dir.mktmpdir('video-poster') do |dir|
      source = File.join(dir, "source#{File.extname(attachment.file.filename.to_s)}")
      output = File.join(dir, 'poster.jpg')
      attachment.file.blob.open { |file| FileUtils.cp(file.path, source) }
      Video::PosterExtractor.new(source).extract(output) && store(attachment, output)
    end
  rescue ActiveStorage::FileNotFoundError
    raise
  rescue StandardError => e
    Rails.logger.error("[Attachments::VideoPosterJob] FALHOU att=#{attachment.id}: #{e.class}: #{e.message}")
    false
  end

  # Dentro do bloco: o upload roda no commit e le o arquivo aberto.
  def store(attachment, path)
    File.open(path) do |io|
      attachment.poster.attach(io: io, filename: "#{attachment.file.filename.base}.jpg", content_type: 'image/jpeg')
    end
  end

  # So a tela, como no Attachments::Mp4ConversionJob: um `message_updated` pelo webhook chegaria a ponte da WAHA
  # antes do `message_created` de um envio ainda na fila.
  def refresh_bubble(attachment)
    message = attachment.message.reload
    ActionCableListener.instance.message_updated(Events::Base.new(::Events::Types::MESSAGE_UPDATED, Time.zone.now, message: message))
  end
end
