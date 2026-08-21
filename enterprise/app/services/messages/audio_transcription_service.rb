class Messages::AudioTranscriptionService< Llm::LegacyBaseOpenAiService
  # Limite duro do endpoint de transcricao da OpenAI: 25 MB DECIMAIS (25_000_000), nao
  # binarios (25.megabytes = 26_214_400) — usar a forma binaria vaza a faixa 25,0–26,2 MB
  # para a API como 413. Audio longo (~70+ min em Opus) mantem o anexo e pula a transcricao.
  TRANSCRIPTION_BYTE_LIMIT = 25_000_000
  include Integrations::LlmInstrumentation

  WHISPER_MODEL = 'whisper-1'.freeze

  attr_reader :attachment, :message, :account

  def initialize(attachment)
    @attachment = attachment
    @message = attachment.message
    @account = message.account
    super()
  end

  def perform
    bloqueio = motivo_para_nao_transcrever
    return bloqueio if bloqueio

    transcriptions = transcribe_audio
    Rails.logger.info "Audio transcription successful: #{transcriptions}"
    { success: true, transcriptions: transcriptions }
  rescue Faraday::UnauthorizedError
    Rails.logger.warn("[AudioTranscription] 401 OpenAI (chave inválida/desabilitada) att=#{attachment&.id} acc=#{account&.id}")
    { error: 'OpenAI configuration is invalid or disabled (401)' }
  rescue Faraday::Error => e
    # Transcrição é best-effort: rate limit (429), 5xx, timeout ou falha de conexão da
    # OpenAI NÃO podem abortar o atendimento. Sem este rescue, o erro sobe pelo builder
    # de histórico e derruba a resposta inteira (IA fica muda). Degrada para "sem
    # transcrição" — o chamador já trata `{ error: ... }` como texto vazio. Log VISÍVEL
    # (att/acc) porque era exatamente esse erro que sumia sem rastro (rate limit da key).
    Rails.logger.warn("[AudioTranscription] FALHOU após retry: #{e.class} att=#{attachment&.id} acc=#{account&.id}")
    { error: "OpenAI request failed (#{e.class})" }
  end

  private

  # Áudio (Whisper) usa uma key OpenAI própria, com fallback pra CAPTAIN_OPEN_AI_API_KEY.
  def api_key_config_name
    'AUDIO_OPEN_AI_API_KEY'
  end

  def can_transcribe?
    # Captain v2 ("AI Agents") is the canonical flag; 'captain_integration' is the
    # legacy one (hidden from the super-admin UI). Accounts migrated to v2 can end up
    # with v2 on but legacy off — accept either so audio still transcribes.
    return false unless account.feature_enabled?('captain_integration') || account.feature_enabled?('captain_integration_v2')
    return false if account.audio_transcriptions.blank?

    account.usage_limits[:captain][:responses][:current_available].positive?
  end

  # As tres recusas antes de gastar chamada no Whisper, num metodo so: mantem a ORDEM
  # original (cota -> mensagem -> tamanho) e tira 3 ramos do `perform`, que ja estourava
  # o Metrics/CyclomaticComplexity antes desta mudanca.
  def motivo_para_nao_transcrever
    return { error: 'Transcription limit exceeded' } unless can_transcribe?
    return { error: 'Message not found' } if message.blank?
    return { error: 'Audio too large for Whisper' } if audio_too_large?

    nil
  end

  def audio_too_large?
    blob = attachment.file&.blob
    return false unless blob

    blob.byte_size > TRANSCRIPTION_BYTE_LIMIT
  end

  def fetch_audio_file
    blob = attachment.file.blob
    temp_dir = Rails.root.join('tmp/uploads/audio-transcriptions')
    FileUtils.mkdir_p(temp_dir)
    temp_file_name = "#{blob.key}-#{blob.filename}"

    if blob.filename.extension_without_delimiter.blank?
      extension = extension_from_content_type(blob.content_type)
      temp_file_name = "#{temp_file_name}.#{extension}" if extension.present?
    end

    temp_file_path = File.join(temp_dir, temp_file_name)

    File.open(temp_file_path, 'wb') do |file|
      blob.open do |blob_file|
        IO.copy_stream(blob_file, file)
      end
    end

    temp_file_path
  end

  def transcribe_audio
    transcribed_text = attachment.meta&.[]('transcribed_text') || ''
    return transcribed_text if transcribed_text.present?

    temp_file_path = fetch_audio_file
    transcribed_text = whisper_with_retry(temp_file_path)

    update_transcription(transcribed_text)
    transcribed_text
  ensure
    FileUtils.rm_f(temp_file_path) if temp_file_path.present?
  end

  # 1 retry: um 429/timeout/5xx transitório da OpenAI deixava o áudio SEM transcrição em
  # silêncio (best-effort). Agora tenta de novo antes de desistir. 401/400 não repete.
  def whisper_with_retry(path)
    tries = 0
    begin
      tries += 1
      File.open(path, 'rb') do |file|
        @client.audio.transcribe(parameters: { model: WHISPER_MODEL, file: file, temperature: 0.4 })['text']
      end
    rescue Faraday::UnauthorizedError, Faraday::BadRequestError
      raise
    rescue Faraday::Error => e
      raise if tries >= 2

      Rails.logger.warn("[AudioTranscription] retry após #{e.class} (att=#{attachment&.id} acc=#{account&.id})")
      sleep(1)
      retry
    end
  end

  def instrumentation_params(file_path)
    {
      span_name: 'llm.messages.audio_transcription',
      model: WHISPER_MODEL,
      account_id: account&.id,
      feature_name: 'audio_transcription',
      file_path: file_path
    }
  end

  def update_transcription(transcribed_text)
    return if transcribed_text.blank?

    attachment.update!(meta: { transcribed_text: transcribed_text })
    message.reload.send_update_event
    message.account.increment_response_usage

    return unless ChatwootApp.advanced_search_allowed?

    message.reindex
  end

  def extension_from_content_type(content_type)
    subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
    return if subtype.blank?

    {
      'x-m4a' => 'm4a',
      'x-wav' => 'wav',
      'x-mp3' => 'mp3'
    }.fetch(subtype, subtype)
  end
end
