# Converte um video .MOV (QuickTime, o formato da camera do iPhone) em .mp4 H.264 + AAC: o unico
# formato de video que o WhatsApp oficial aceita e que o Chrome (e o app desktop) toca sempre.
#
# Usa o mesmo `ffmpeg` da frota que o Audio::WaveformExtractor e o Captain::VideoFrameExtractor.
# Devolve false quando o ffmpeg nao existe, falha ou passa do tempo — nunca levanta: quem chama
# segue com o arquivo original.
class Video::Mp4Converter
  # Abaixo da espera maxima do envio (AttachmentMp4Conversion::MP4_WAIT_LIMIT), para a conversao terminar antes
  # de o envio desistir de esperar.
  TIMEOUT_SECONDS = 540
  # Lado maior em 720p, perto do que o proprio WhatsApp manda: 4K do iPhone recodificado sairia
  # grande demais para o limite de 16 MB e lento demais para a VM.
  MAX_SIDE = 1280

  def initialize(source_path)
    @source_path = source_path
  end

  def convert(output_path)
    output, status = Open3.capture2e('timeout', TIMEOUT_SECONDS.to_s, ffmpeg_path, '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
                                     '-i', @source_path, '-map', '0:v:0', '-map', '0:a:0?', *video_args,
                                     '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', output_path)
    return true if status.success? && File.size?(output_path).present?

    # Sem ffmpeg (127) ou sem o libx264 ("Unknown encoder"), o motivo fica no log da VM.
    Rails.logger.error("[Video::Mp4Converter] ffmpeg saiu com #{status.exitstatus}: #{output.to_s.strip.last(500)}")
    false
  end

  private

  # Video que ja e H.264 so troca de embalagem (segundos). HEVC, o padrao do iPhone, precisa
  # recodificar; `yuv420p` porque o HDR do iPhone e 10 bits, que navegador e WhatsApp nao tocam.
  def video_args
    return %w[-c:v copy] if h264?

    scale = "scale=w='if(gt(iw,ih),min(#{MAX_SIDE},iw),-2)':h='if(gt(iw,ih),-2,min(#{MAX_SIDE},ih))'"
    ['-vf', scale, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p', '-threads', '2']
  end

  def h264?
    out, status = Open3.capture2(ffprobe_path, '-v', 'error', '-select_streams', 'v:0',
                                 '-show_entries', 'stream=codec_name', '-of', 'default=nw=1:nk=1', @source_path, err: File::NULL)
    status.success? && out.strip == 'h264'
  rescue SystemCallError
    false
  end

  def ffmpeg_path
    ENV.fetch('FFMPEG_PATH', 'ffmpeg')
  end

  def ffprobe_path
    ENV.fetch('FFPROBE_PATH', 'ffprobe')
  end
end
