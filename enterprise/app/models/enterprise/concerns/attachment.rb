module Enterprise::Concerns::Attachment
  extend ActiveSupport::Concern

  included do
    after_create_commit :enqueue_audio_transcription
    after_create_commit :enqueue_media_description
  end

  private

  def enqueue_audio_transcription
    return unless file_type.to_sym == :audio

    Messages::AudioTranscriptionJob.perform_later(id)
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
