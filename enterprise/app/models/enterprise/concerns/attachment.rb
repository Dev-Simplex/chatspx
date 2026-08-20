module Enterprise::Concerns::Attachment
  extend ActiveSupport::Concern

  included do
    after_create_commit :enqueue_audio_transcription
    # Broadcast the message update so the FE bubble picks up the new audio
    # attachment immediately. Without this, the FE has to wait until Whisper
    # finishes (or fall back to a page refresh) — and if Whisper returns blank,
    # the bubble never gets the audio at all.
    after_create_commit :broadcast_message_update_for_audio
    after_create_commit :enqueue_media_description
  end

  private

  def enqueue_audio_transcription
    return unless file_type.to_sym == :audio

    # No file.attached? guard: the social-media ingest path saves the
    # Attachment before attaching the blob. AudioTranscriptionJob retries
    # on ActiveStorage::FileNotFoundError to ride out that race.
    Messages::AudioTranscriptionJob.perform_later(id)
  end

  def broadcast_message_update_for_audio
    return unless file_type.to_sym == :audio
    return unless message
    # Without an attached file, the message serializer's audio_metadata path
    # dereferences `file.metadata[:width]` on nil and raises. The pre-attach
    # broadcast wouldn't carry useful audio info anyway — skip until upload completes.
    return unless file.attached?

    message.reload.send_update_event
  end

  # Descreve a midia AQUI, na chegada, e nao no momento em que o agente monta o contexto:
  # o builder monta o historico INTEIRO a cada turno, e enfileirar de la faria uma conversa
  # com dezenas de fotos antigas disparar dezenas de chamadas por turno. Enfileirando na
  # criacao, a descricao costuma estar pronta quando o agente roda (o debounce sozinho ja
  # da alguns segundos) e cada imagem e descrita uma unica vez na vida.
  def enqueue_media_description
    return if message.blank? || !message.incoming?
    return unless media_pipeline_wanted?

    Captain::MediaDescriptionJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[MediaDescription] falha ao agendar descricao att=#{id}: #{e.class}: #{e.message}")
  end

  # Filtro GROSSO, de proposito: este hook roda no commit do anexo, quando o blob pode nem
  # estar disponivel — entao a decisao aqui e pelo file_type, e quem refina pelo content_type
  # e o servico (um :ig_story de foto cai fora la, sem custo). Reply a story do Instagram
  # chega como :ig_story tanto em foto quanto em video; :ig_reel, idem.
  def media_pipeline_wanted?
    politica = Captain::Behavior::MediaPipelineService
    return politica.image_description_enabled_for?(account) if Captain::MediaDescriptionService::SUPPORTED_FILE_TYPES.include?(file_type.to_s)
    return politica.video_enabled_for?(account) if %w[video ig_story ig_reel].include?(file_type.to_s)

    false
  end
end
