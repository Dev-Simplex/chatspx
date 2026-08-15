class Captain::Behavior::MediaPipelineService
  IMAGE_DESCRIPTION_KEY = 'image_description'.freeze
  VIDEO_DESCRIPTION_KEY = 'video_description'.freeze
  VIDEO_TRANSCRIPTION_KEY = 'video_transcription'.freeze
  VIDEO_KEYS = [VIDEO_DESCRIPTION_KEY, VIDEO_TRANSCRIPTION_KEY].freeze

  # Opt-in por CONTA. A chave vive no behavior do agente (e la que o operador a liga, via
  # API de configuracao), mas o hook de anexo so conhece a conta — entao a pergunta e "algum
  # agente desta conta pediu descricao de imagem?". Conta sem nenhum agente com a chave nao
  # descreve nada e nao muda de comportamento.
  def self.image_description_enabled_for?(account)
    key_enabled_for?(account, IMAGE_DESCRIPTION_KEY)
  end

  # Video tem DUAS chaves independentes porque o custo e o proveito mudam por cliente, e
  # isso foi medido, nao suposto. No story da Tozi (conta 6) os quadros trazem o dado
  # escrito na tela — codigo do imovel, preco, metragem — enquanto o audio e trilha
  # musical: o Whisper devolveu "Music Plays" seguido de uma fila de emoji, que no
  # contexto do agente e poluicao, nao informacao. Ja na BigStore a informacao do produto
  # e NARRADA no video. Quem liga uma nao paga pela outra.
  def self.video_description_enabled_for?(account)
    key_enabled_for?(account, VIDEO_DESCRIPTION_KEY)
  end

  def self.video_transcription_enabled_for?(account)
    key_enabled_for?(account, VIDEO_TRANSCRIPTION_KEY)
  end

  # Usada pelo hook de anexo, que so precisa saber se vale enfileirar: o job decide qual
  # das duas metades roda.
  def self.video_enabled_for?(account)
    VIDEO_KEYS.any? { |key| key_enabled_for?(account, key) }
  end

  def self.key_enabled_for?(account, key)
    return false if account.blank?

    Captain::Assistant.where(account_id: account.id)
                      .exists?(["behavior -> 'media_pipeline' ->> ? = 'true'", key])
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

  def video_description?
    @config[VIDEO_DESCRIPTION_KEY] == true
  end

  def video_transcription?
    @config[VIDEO_TRANSCRIPTION_KEY] == true
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
