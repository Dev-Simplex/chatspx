# Camada midia -> contexto: transforma um anexo em TEXTO que o agente le junto da conversa.
#
# Trata IMAGEM e VIDEO. O video entra por QUADROS (ffmpeg), nao pelo arquivo: nenhum modelo
# de visao come mp4, e o que interessa na pratica esta escrito na tela. Medido no story da
# conta 6 (54s, 720x1280): tres quadros bastaram pra ler codigo do imovel, preco, metragem e
# telefone. O `ffmpeg` ja estava instalado na frota (6.1.1) — o ActiveStorage o usa pra
# analisar o blob —, entao o "precisa antes de ferramenta na VM" que deixou video de fora
# nao era mais verdade.
#
# Chave e modelo sao resolvidos POR CONTA com fallback global (Copilot::OpenaiSettings), e NAO
# pela InstallationConfig global que o modelo do agente usa. Midia e o custo que mais varia de
# cliente pra cliente; resolvendo por conta, cada um paga (e limita) o proprio consumo.
class Captain::MediaDescriptionService
  SUPPORTED_FILE_TYPES = %w[image].freeze
  META_KEY = 'media_description'.freeze
  TRANSCRIPTION_META_KEY = 'media_transcription'.freeze
  MAX_BYTES = 10.megabytes
  MAX_TOKENS = 350

  # Tres quadros: comeco, meio e fim. Story costuma trocar de cena e repetir o dado escrito
  # em todas elas, entao mais quadros pagam mais pelo mesmo texto.
  FRAME_POSITIONS = [0.15, 0.5, 0.85].freeze
  FRAME_WIDTH = 768
  FALLBACK_DURATION = 10.0
  # Teto da API de transcricao da OpenAI. Acima disso o request volta 413 e o rescue engoliria.
  MAX_TRANSCRIPTION_BYTES = 25.megabytes
  WHISPER_MODEL = 'whisper-1'.freeze

  # Video se reconhece pelo content_type do blob, nao pelo file_type: o reply a story do
  # Instagram chega como :ig_story tanto em foto quanto em video, e e justamente o de video
  # que ficava invisivel pro agente.
  def self.video?(attachment)
    return false if attachment.blank?
    return attachment.file.blob.content_type.to_s.start_with?('video/') if attachment.file.attached?

    attachment.file_type.to_s == 'video'
  end

  def initialize(attachment:, account: nil)
    @attachment = attachment
    @account = account || attachment&.account
  end

  def perform
    return nil if attachment.blank?
    return nil unless SUPPORTED_FILE_TYPES.include?(attachment.file_type.to_s) || video?
    return cached if cached.present?
    return missing_key_warning if api_key.blank?

    text = video? ? describe_video : describe
    persist(META_KEY, text) if text.present?
    text
  end

  # Metade independente da descricao: quem liga uma nao paga a outra. Vale so pra video —
  # audio de mensagem continua no Messages::AudioTranscriptionService, que tem quota e
  # gate proprios e ja roda em producao.
  def transcribe
    return nil if attachment.blank? || !video?
    return cached_transcription if cached_transcription.present?
    return missing_key_warning if api_key.blank?

    text = transcribe_video
    persist(TRANSCRIPTION_META_KEY, text) if text.present?
    text
  end

  private

  attr_reader :attachment, :account

  def api_key
    @api_key ||= Copilot::OpenaiSettings.api_key(account)
  end

  def model
    @model ||= Copilot::OpenaiSettings.vision_model(account)
  end

  def video?
    self.class.video?(attachment)
  end

  def cached
    attachment.meta&.[](META_KEY).to_s.strip.presence
  end

  def cached_transcription
    attachment.meta&.[](TRANSCRIPTION_META_KEY).to_s.strip.presence
  end

  # Chave ausente e configuracao, nao incidente: nao vai pro tracker, mas tambem nao passa
  # em silencio — sem esta linha o operador liga a flag, nada acontece e nao ha o que olhar.
  def missing_key_warning
    Rails.logger.warn("[MediaDescription] sem chave OpenAI pra conta acc=#{account&.id} att=#{attachment&.id} — descricao ignorada")
    nil
  end

  def describe
    source = image_source
    return nil if source.blank?

    response = OpenAI::Client.new(access_token: api_key).chat(parameters: chat_parameters(source))
    Copilot::OpenaiSettings.log_chat_usage(service: 'media_description', account: account, model: model, response: response)
    response.dig('choices', 0, 'message', 'content').to_s.strip.presence
  rescue StandardError => e
    report_failure(e)
    nil
  end

  # Video vira UMA chamada de visao com os quadros em ordem — nao uma por quadro. O modelo
  # precisa ver a sequencia junta pra nao repetir tres vezes o mesmo dado escrito na tela.
  def describe_video
    with_local_copy do |path|
      frames = extract_frames(path)
      return nil if frames.empty?

      sources = frames.map { |f| "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(f))}" }
      response = OpenAI::Client.new(access_token: api_key).chat(parameters: video_chat_parameters(sources))
      Copilot::OpenaiSettings.log_chat_usage(service: 'media_description_video', account: account, model: model, response: response)
      response.dig('choices', 0, 'message', 'content').to_s.strip.presence
    end
  rescue StandardError => e
    report_failure(e)
    nil
  end

  # O Whisper aceita mp4 direto (provado com o story de 9,3 MB da conta 6), entao nao ha
  # extracao de trilha aqui: so o teto de tamanho da propria API.
  def transcribe_video
    blob = attachment.file.attached? ? attachment.file.blob : nil
    return oversized_warning(blob.byte_size, 'transcricao') if blob && blob.byte_size > MAX_TRANSCRIPTION_BYTES

    with_local_copy do |path|
      File.open(path, 'rb') do |file|
        OpenAI::Client.new(access_token: api_key)
                      .audio.transcribe(parameters: { model: WHISPER_MODEL, file: file, temperature: 0.4 })['text']
                      .to_s.strip.presence
      end
    end
  rescue StandardError => e
    report_failure(e)
    nil
  end

  # O arquivo precisa estar em disco pro ffmpeg e pro upload da transcricao. Anexo so-externo
  # (canal que nao baixou a midia) nao tem o que copiar — nesse caso nao ha video a ler.
  def with_local_copy
    return nil unless attachment.file.attached?

    blob = attachment.file.blob
    dir = Rails.root.join('tmp/uploads/media-description', "att-#{attachment.id}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "source#{File.extname(blob.filename.to_s).presence || '.mp4'}")
    File.open(path, 'wb') { |f| blob.open { |source| IO.copy_stream(source, f) } }
    yield(path)
  ensure
    FileUtils.rm_rf(dir) if dir.present?
  end

  # Quadros em pontos proporcionais a duracao. A duracao vem do metadata que o ActiveStorage
  # ja gravou (ele mesmo usa ffprobe); sem ela, um fallback curto ainda pega o inicio.
  def extract_frames(path)
    duration = attachment.file.blob.metadata['duration'].to_f
    duration = FALLBACK_DURATION if duration <= 0

    FRAME_POSITIONS.each_with_index.filter_map do |position, index|
      out = File.join(File.dirname(path), "frame-#{index}.jpg")
      ok = system('ffmpeg', '-loglevel', 'error', '-y', '-ss', (duration * position).round(1).to_s,
                  '-i', path, '-frames:v', '1', '-vf', "scale=#{FRAME_WIDTH}:-1", '-q:v', '4', out,
                  out: File::NULL, err: File::NULL)
      next ffmpeg_warning(index) unless ok && File.exist?(out) && File.size(out).positive?

      out
    end
  end

  # `system` devolve nil quando o binario nao existe e false quando ele falha. Os dois casos
  # sao configuracao de VM, nao incidente — mas precisam aparecer, senao o operador liga a
  # chave, nao acontece nada e nao ha o que olhar.
  def ffmpeg_warning(index)
    Rails.logger.warn("[MediaDescription] ffmpeg nao extraiu o quadro #{index} att=#{attachment&.id} acc=#{account&.id}")
    nil
  end

  # Falha aqui NAO pode derrubar a resposta ao cliente — a imagem continua indo como visao
  # direta e o agente responde igual. Mas tambem nao pode sumir: log em ERROR com anexo,
  # conta e modelo, e captura no tracker. Rescue mudo foi exatamente o que ja deixou cliente
  # sem resposta por horas sem nenhum rastro no caminho do audio.
  def report_failure(error)
    Rails.logger.error(
      "[MediaDescription] FALHOU att=#{attachment&.id} acc=#{account&.id} model=#{model} #{error.class}: #{error.message}"
    )
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  # Data URL (base64) quando o arquivo esta no storage: a URL do anexo pode ser assinada,
  # interna ou inacessivel de fora, e nesse caso a OpenAI receberia um 404 no lugar da imagem.
  # Anexo so-externo (canal que nao baixa o arquivo) vai pela URL mesmo.
  def image_source
    return external_source unless attachment.file.attached?

    blob = attachment.file.blob
    return oversized_warning(blob.byte_size) if blob.byte_size > MAX_BYTES

    "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.download)}"
  end

  def external_source
    attachment.external_url.presence || attachment.download_url.presence
  end

  def oversized_warning(byte_size, etapa = 'descricao')
    Rails.logger.warn("[MediaDescription] midia acima do limite att=#{attachment.id} bytes=#{byte_size} — #{etapa} ignorada")
    nil
  end

  def chat_parameters(source)
    {
      model: model,
      max_tokens: MAX_TOKENS,
      temperature: 0.2,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: [{ type: 'image_url', image_url: { url: source } }] }
      ]
    }
  end

  # Descritivo puro: o texto entra no contexto do agente, entao nao pode conter conclusao,
  # suposicao nem completar o que estiver cortado — o agente trataria isso como fato do
  # cliente. Sem exemplo de resposta no prompt, de proposito: exemplo vira molde e o modelo
  # devolve o exemplo quando nao enxerga a imagem.
  def system_prompt
    <<~PROMPT
      Descreva o conteudo desta imagem para alguem que nao pode ve-la.
      Escreva em #{language}, em texto corrido, no maximo 4 frases.
      Relate apenas o que esta visivel: objetos, pessoas, cenario e o texto legivel na
      imagem, transcrito literalmente.
      Nao interprete intencao, nao conclua nada alem do que se ve e nao complete informacao
      cortada, borrada ou ilegivel.
      Se a imagem estiver ilegivel ou sem conteudo, diga isso e pare.
    PROMPT
  end

  def video_chat_parameters(sources)
    {
      model: model,
      max_tokens: MAX_TOKENS,
      temperature: 0.2,
      messages: [
        { role: 'system', content: video_system_prompt },
        { role: 'user', content: sources.map { |s| { type: 'image_url', image_url: { url: s } } } }
      ]
    }
  end

  # Mesma disciplina do prompt de imagem: descritivo puro, sem conclusao e SEM exemplo de
  # resposta — exemplo vira molde e o modelo devolve o molde quando nao enxerga nada. A
  # instrucao de transcrever o texto da tela literalmente e o que importa aqui: e nele que
  # vem o dado que o cliente esta perguntando.
  def video_system_prompt
    <<~PROMPT
      As imagens a seguir sao quadros de um mesmo video, na ordem em que aparecem.
      Descreva o video para alguem que nao pode ve-lo, em #{language}, em texto corrido,
      no maximo 5 frases.
      Transcreva literalmente todo texto legivel na tela, inclusive numeros e valores.
      Trate os quadros como partes de um unico video: nao repita o que ja disse.
      Nao interprete intencao, nao conclua nada alem do que se ve e nao complete informacao
      cortada, borrada ou ilegivel.
      Se os quadros estiverem ilegiveis ou sem conteudo, diga isso e pare.
    PROMPT
  end

  def language
    account&.locale.to_s.presence || 'pt_BR'
  end

  def persist(key, text)
    new_meta = (attachment.meta || {}).merge(key => text)
    # Sem callbacks/validacao: e metadado do proprio anexo, escrito por um job de
    # background. Mesmo tratamento que o cache de transcricao de audio ja recebe.
    attachment.update_column(:meta, new_meta) # rubocop:disable Rails/SkipsModelValidations
  end
end
