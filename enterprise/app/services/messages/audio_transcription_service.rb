class Messages::AudioTranscriptionService< Llm::LegacyBaseOpenAiService
  include Integrations::LlmInstrumentation

  # OpenAI's transcription endpoint hard limit is 25 MB *decimal* (25_000_000), not
  # binary (25.megabytes = 26_214_400) — using the binary form leaks the 25.0–26.2 MB
  # range to the API as 413s. Long audio (~70+ min Opus) keeps the attachment but skips
  # transcription.
  TRANSCRIPTION_BYTE_LIMIT = 25_000_000

  attr_reader :attachment, :message, :account, :transcription_model

  def initialize(attachment)
    @attachment = attachment
    @message = attachment.message
    @account = message.account
    super()
    @transcription_model = Llm::FeatureRouter.resolve(feature: 'audio_transcription', account: account)[:model]
  end

  def perform
    return { error: 'Transcription limit exceeded' } unless can_transcribe?
    return { error: 'Message not found' } if message.blank?
    return { error: 'Audio too large for Whisper' } if audio_too_large?

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
  #
  # RECONCILIAÇÃO homologacao × v4.16.2 — dois ajustes, e cada um veio de um lado:
  #
  #  · `WHISPER_MODEL` NÃO EXISTE MAIS AQUI. O upstream trocou a constante fixa
  #    ('whisper-1') pelo modelo que o `Llm::FeatureRouter` resolve por conta
  #    (`transcription_model`, definido no `initialize`). Manter a constante faria a primeira
  #    transcrição levantar `NameError` — em runtime, não no boot, porque Ruby só resolve
  #    constante quando a linha executa. O arquivo carregaria, os testes do lado antigo
  #    passariam, e o defeito apareceria no áudio de um cliente.
  #  · `temperature: 0.0`, e não 0.4. É melhoria do upstream com razão medida: em áudio
  #    silencioso ou quase silencioso, temperatura > 0 dispara repetição em espiral — o
  #    modelo "alucina" texto que não foi dito. O comportamento é documentado em todos os
  #    modelos de transcrição da OpenAI.
  #
  # O QUE NÃO MUDOU é a razão de este método existir: o retry é da equipe, e sem ele um 429
  # transitório deixava o áudio sem transcrição em silêncio.
  def whisper_with_retry(path)
    tries = 0
    begin
      tries += 1
      File.open(path, 'rb') do |file|
        @client.audio.transcribe(parameters: { model: transcription_model, file: file, temperature: 0.0 })['text']
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
      model: transcription_model,
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
