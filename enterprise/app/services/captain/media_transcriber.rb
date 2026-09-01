# Transcreve o áudio de um vídeo de anexo. Metade irmã do Captain::VideoFrameExtractor:
# uma lê o que está ESCRITO na tela, esta lê o que é FALADO.
#
# Não extrai trilha de áudio: o Whisper aceita o mp4 direto — provado com um story de 9,3 MB
# da conta 6. O único limite é o de tamanho da própria API.
class Captain::MediaTranscriber
  MODEL = 'whisper-1'.freeze
  # Teto da API de transcrição da OpenAI. Acima disso o request volta 413.
  MAX_BYTES = 25.megabytes

  def initialize(attachment:, api_key:)
    @attachment = attachment
    @api_key = api_key
  end

  # Devolve o texto, ou nil quando não há arquivo local, quando ele passa do teto ou quando a
  # API falha — nunca levanta. Os temporários morrem antes de retornar.
  def call
    return nil unless attachment.file.attached?

    blob = attachment.file.blob
    return oversized(blob.byte_size) if blob.byte_size > MAX_BYTES

    com_copia_local(blob) { |path| transcreve(path) }
  end

  private

  attr_reader :attachment, :api_key

  def transcreve(path)
    File.open(path, 'rb') do |file|
      OpenAI::Client.new(access_token: api_key)
                    .audio.transcribe(parameters: { model: MODEL, file: file, temperature: 0.4 })['text']
                    .to_s.strip.presence
    end
  end

  def com_copia_local(blob)
    dir = Rails.root.join('tmp/uploads/media-description', "att-#{attachment.id}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "source#{File.extname(blob.filename.to_s).presence || '.mp4'}")
    File.open(path, 'wb') { |f| blob.open { |source| IO.copy_stream(source, f) } }
    yield(path)
  ensure
    FileUtils.rm_rf(dir) if dir.present?
  end

  def oversized(byte_size)
    Rails.logger.warn("[MediaTranscriber] acima do limite att=#{attachment.id} bytes=#{byte_size} — transcricao ignorada")
    nil
  end
end
