# Tira o primeiro quadro de um video e grava como JPEG: a previa que a bolha, a barra de midia e a galeria
# mostram antes do play. Sem ela, a previa dependia do navegador desenhar o quadro sozinho, e o Chrome/Edge
# no Windows (e o app desktop) nao desenham com `preload="metadata"`: a bolha ficava vazia, so com o play.
#
# Devolve false quando o ffmpeg nao existe, falha ou passa do tempo — nunca levanta: sem previa, a bolha
# segue como antes.
class Video::PosterExtractor
  TIMEOUT_SECONDS = 60
  # Largura da bolha no maior layout; o lado menor de video em pe tambem cabe aqui.
  MAX_WIDTH = 480

  def initialize(source_path)
    @source_path = source_path
  end

  def extract(output_path)
    # `-threads 2`: roda no worker, que tem teto de memoria (ver Video::Mp4Converter#decoder_args). A rotacao do
    # celular ja vem aplicada (autorotate do ffmpeg), entao video em pe vira imagem em pe.
    output, status = Open3.capture2e('timeout', TIMEOUT_SECONDS.to_s, ffmpeg_path, '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
                                     '-threads', '2', '-i', @source_path, '-frames:v', '1',
                                     '-vf', "scale=w='min(#{MAX_WIDTH},iw)':h=-2", '-q:v', '4', output_path)
    return true if status.success? && File.size?(output_path).present?

    Rails.logger.error("[Video::PosterExtractor] ffmpeg saiu com #{status.exitstatus}: #{output.to_s.strip.last(500)}")
    false
  rescue SystemCallError => e
    Rails.logger.error("[Video::PosterExtractor] #{e.class}: #{e.message}")
    false
  end

  private

  def ffmpeg_path
    ENV.fetch('FFMPEG_PATH', 'ffmpeg')
  end
end
