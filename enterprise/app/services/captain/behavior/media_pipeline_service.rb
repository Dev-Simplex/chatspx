class Captain::Behavior::MediaPipelineService
  IMAGE_DESCRIPTION_KEY = 'image_description'.freeze

  # Opt-in por CONTA. A chave vive no behavior do agente (e la que o operador a liga, via
  # API de configuracao), mas o hook de anexo so conhece a conta — entao a pergunta e "algum
  # agente desta conta pediu descricao de imagem?". Conta sem nenhum agente com a chave nao
  # descreve nada e nao muda de comportamento.
  def self.image_description_enabled_for?(account)
    return false if account.blank?

    Captain::Assistant.where(account_id: account.id)
                      .exists?(["behavior -> 'media_pipeline' ->> ? = 'true'", IMAGE_DESCRIPTION_KEY])
  end

  def initialize(assistant:, message:)
    @assistant = assistant
    @message = message
    @config = assistant&.behavior&.dig('media_pipeline') || {}
  end

  def process
    return nil unless enabled?

    transcribe_audio || ''
  end

  # Publico porque quem INJETA a descricao no contexto (Captain::OpenAiMessageBuilderService)
  # consulta esta politica: desligar a chave para de escrever descricao nova E para de
  # injetar as ja gravadas, no mesmo gesto.
  def image_description?
    @config[IMAGE_DESCRIPTION_KEY] == true
  end

  private

  def enabled?
    @config['audio_transcription'] || @config['image_description']
  end

  def transcribe_audio
    return unless @config['audio_transcription']

    audio_attachment = @message.attachments.find { |a| a.file_type == 'audio' }
    return unless audio_attachment

    Messages::AudioTranscriptionService.new(message: @message).process
  end
end
