class AudioTranscriptionService
  WHISPER_MODEL = 'whisper-1'.freeze
  MAX_BYTES = 24.megabytes # OpenAI Whisper limit is 25MB; keep margin

  def initialize(attachment:, language: 'pt', account: nil)
    @attachment = attachment
    @language = language
    @account = account || attachment&.account
  end

  def perform
    return nil if api_key.blank?
    return nil unless attachment.file_type.to_s == 'audio'
    return existing if existing.present?

    text = transcribe
    persist_text(text) if text.present?
    text
  end

  private

  attr_reader :attachment, :language

  def api_key
    @api_key ||= Copilot::OpenaiSettings.api_key(@account)
  end

  def existing
    attachment.meta&.[]('transcribed_text').to_s.strip.presence
  end

  def transcribe
    blob = audio_blob
    return nil if blob.blank?

    Tempfile.create(['transcribe', file_extension], binmode: true) do |tmp|
      tmp.write(blob)
      tmp.rewind
      response = OpenAI::Client.new(access_token: api_key).audio.transcribe(
        parameters: { model: WHISPER_MODEL, file: tmp, language: language }
      )
      log_telemetry(blob.bytesize)
      response.is_a?(Hash) ? response['text'].to_s.strip.presence : nil
    end
  rescue StandardError => e
    Rails.logger.warn("[AudioTranscriptionService] #{e.class}: #{e.message}")
    nil
  end

  def log_telemetry(bytes)
    # Coarse heuristic: opus/m4a ~16kbps voz típica → bytes/2000 ~= duração em segundos
    duration_seconds = (bytes / 2000.0).round
    Copilot::OpenaiSettings.log_audio_usage(service: 'audio_transcription', account: @account, duration_seconds: duration_seconds)
  end

  def audio_blob
    if attachment.file.attached?
      blob = attachment.file.blob
      return nil if blob.byte_size > MAX_BYTES

      blob.download
    elsif attachment.external_url.present?
      Net::HTTP.get(URI.parse(attachment.external_url)).force_encoding('BINARY')
    end
  end

  def file_extension
    ext = attachment.extension.to_s.strip.delete_prefix('.')
    ext.present? ? ".#{ext}" : '.ogg'
  end

  def persist_text(text)
    new_meta = (attachment.meta || {}).merge('transcribed_text' => text)
    # Skip callbacks: this is metadata-only and would otherwise re-trigger transcription.
    attachment.update_column(:meta, new_meta) # rubocop:disable Rails/SkipsModelValidations
    notify_message_updated
  end

  def notify_message_updated
    message = attachment.message
    return if message.blank?

    Rails.configuration.dispatcher.dispatch(
      ::Events::Types::MESSAGE_UPDATED,
      Time.zone.now,
      message: message.reload,
      performed_by: nil
    )
  end
end
