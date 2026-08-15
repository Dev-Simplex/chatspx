# Camada midia -> contexto: transforma um anexo em TEXTO que o agente le junto da conversa.
#
# Hoje trata IMAGEM. A forma comporta outros tipos (ver SUPPORTED_FILE_TYPES): video precisa
# antes de ferramenta na VM (ffmpeg pra extrair audio e quadros) e por isso ficou de fora.
#
# Chave e modelo sao resolvidos POR CONTA com fallback global (Copilot::OpenaiSettings), e NAO
# pela InstallationConfig global que o modelo do agente usa. Midia e o custo que mais varia de
# cliente pra cliente; resolvendo por conta, cada um paga (e limita) o proprio consumo.
class Captain::MediaDescriptionService
  SUPPORTED_FILE_TYPES = %w[image].freeze
  META_KEY = 'media_description'.freeze
  MAX_BYTES = 10.megabytes
  MAX_TOKENS = 350

  def initialize(attachment:, account: nil)
    @attachment = attachment
    @account = account || attachment&.account
  end

  def perform
    return nil if attachment.blank?
    return nil unless SUPPORTED_FILE_TYPES.include?(attachment.file_type.to_s)
    return cached if cached.present?
    return missing_key_warning if api_key.blank?

    text = describe
    persist(text) if text.present?
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

  def cached
    attachment.meta&.[](META_KEY).to_s.strip.presence
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

  def oversized_warning(byte_size)
    Rails.logger.warn("[MediaDescription] imagem acima do limite att=#{attachment.id} bytes=#{byte_size} — descricao ignorada")
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

  def language
    account&.locale.to_s.presence || 'pt_BR'
  end

  def persist(text)
    new_meta = (attachment.meta || {}).merge(META_KEY => text)
    # Sem callbacks/validacao: e metadado do proprio anexo, escrito por um job de
    # background. Mesmo tratamento que o cache de transcricao de audio ja recebe.
    attachment.update_column(:meta, new_meta) # rubocop:disable Rails/SkipsModelValidations
  end
end
