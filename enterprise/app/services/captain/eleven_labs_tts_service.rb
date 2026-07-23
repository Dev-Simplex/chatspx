require 'open3'

# Captain::ElevenLabsTtsService
#
# Gera fala (TTS) na ElevenLabs com a voz exclusiva do assistente e converte o MP3
# pra OGG/Opus via ffmpeg — o formato que o WhatsApp renderiza como VOICE NOTE
# (bolha de PTT); MP3 puro chegaria como arquivo de áudio comum.
#
# Config por ASSISTENTE (config JSONB — dado por conta, nunca no molde compartilhado):
#   voice_id       -> voz ElevenLabs exclusiva do agente (sem ela, áudio indisponível)
#   voice_model    -> modelo TTS (default eleven_v3; voz clonada simples pode preferir
#                     eleven_multilingual_v2)
#   voice_settings -> overrides parciais de DEFAULT_VOICE_SETTINGS
#
# Credencial por CONTA (nunca em código nem em log), mesma escada das demais:
#   account.custom_attributes['elevenlabs_api_key'] -> InstallationConfig
#   ELEVENLABS_API_KEY -> ENV ELEVENLABS_API_KEY.
class Captain::ElevenLabsTtsService
  class Error < StandardError; end

  API_BASE = 'https://api.elevenlabs.io'.freeze
  DEFAULT_MODEL = 'eleven_v3'.freeze
  OUTPUT_FORMAT = 'mp3_44100_128'.freeze
  DEFAULT_VOICE_SETTINGS = {
    'stability' => 0.5,
    'similarity_boost' => 0.75,
    'style' => 0,
    'use_speaker_boost' => true,
    'speed' => 1.0
  }.freeze
  HTTP_TIMEOUT = 40 # segundos — TTS de texto curto responde em poucos segundos
  FFMPEG_TIMEOUT = 30

  def initialize(assistant)
    @assistant = assistant
  end

  def configured?
    voice_id.present? && api_key.present?
  end

  def voice_id
    @assistant&.config&.[]('voice_id').presence
  end

  # Retorna { io:, filename:, content_type: } com o áudio OGG/Opus pronto pra anexar
  # numa mensagem (file_type :audio). Levanta Error em QUALQUER falha — o chamador
  # decide o fallback (a tool instrui o agente a responder em texto).
  def synthesize(text)
    raise Error, 'voice_id ou credencial ElevenLabs ausentes' unless configured?

    ogg = convert_to_ogg_opus(generate_speech(prepare_text(text)))
    { io: StringIO.new(ogg), filename: "voz-#{Time.current.to_i}.ogg", content_type: 'audio/ogg' }
  end

  private

  def model
    @assistant&.config&.[]('voice_model').presence || DEFAULT_MODEL
  end

  def voice_settings
    overrides = @assistant&.config&.[]('voice_settings')
    DEFAULT_VOICE_SETTINGS.merge(overrides.is_a?(Hash) ? overrides : {})
  end

  # Audio tags entre colchetes só funcionam na família v3 — os demais modelos LEEM
  # as tags literalmente. Fora do v3, remove qualquer tag do texto falado.
  def prepare_text(text)
    text = text.to_s
    return text if model.start_with?('eleven_v3')

    text.gsub(/\[[^\]\n]{1,40}\]/, '').squeeze(' ').strip
  end

  def generate_speech(text)
    response = HTTParty.post(
      "#{API_BASE}/v1/text-to-speech/#{voice_id}",
      query: { output_format: OUTPUT_FORMAT },
      headers: { 'xi-api-key' => api_key, 'Content-Type' => 'application/json' },
      body: { text: text, model_id: model, voice_settings: voice_settings }.to_json,
      timeout: HTTP_TIMEOUT
    )
    raise Error, "ElevenLabs HTTP #{response.code}: #{response.body.to_s.byteslice(0, 200)}" unless response.code == 200
    raise Error, 'ElevenLabs devolveu áudio vazio' if response.body.blank?

    response.body
  end

  # MP3 -> OGG/Opus mono (padrão de voice note do WhatsApp). Sem ffmpeg / falha -> Error.
  def convert_to_ogg_opus(mp3_bytes)
    src = Tempfile.new(['captain_tts', '.mp3'])
    src.binmode
    src.write(mp3_bytes)
    src.flush
    dst_path = src.path.sub(/\.mp3\z/, '.ogg')
    run_ffmpeg(src.path, dst_path)
    File.binread(dst_path)
  ensure
    src&.close!
    FileUtils.rm_f(dst_path) if dst_path
  end

  def run_ffmpeg(src_path, dst_path)
    cmd = [
      ffmpeg_path, '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
      '-i', src_path,
      '-c:a', 'libopus', '-b:a', '32k', '-ar', '48000', '-ac', '1', '-application', 'voip',
      dst_path
    ]
    _stdout, stderr, status = Timeout.timeout(FFMPEG_TIMEOUT) { Open3.capture3(*cmd) }
    return if status&.success? && File.exist?(dst_path) && File.size(dst_path).positive?

    raise Error, "ffmpeg falhou: #{stderr.to_s.lines.last.to_s.strip.presence || 'sem saída'}"
  rescue Errno::ENOENT
    raise Error, 'ffmpeg não encontrado no PATH (defina FFMPEG_PATH se necessário)'
  rescue Timeout::Error
    raise Error, "ffmpeg excedeu #{FFMPEG_TIMEOUT}s"
  end

  def ffmpeg_path
    ENV.fetch('FFMPEG_PATH', 'ffmpeg')
  end

  def api_key
    account = @assistant&.account
    (account&.custom_attributes || {})['elevenlabs_api_key'].presence ||
      InstallationConfig.find_by(name: 'ELEVENLABS_API_KEY')&.value.presence ||
      ENV['ELEVENLABS_API_KEY'].presence
  end
end
