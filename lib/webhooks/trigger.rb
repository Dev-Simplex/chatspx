class Webhooks::Trigger
  SUPPORTED_ERROR_HANDLE_EVENTS = %w[message_created message_updated].freeze
  RETRYABLE_AGENT_BOT_STATUSES = [429, 500].freeze

  # Erros que nao melhoram na segunda tentativa. URL invalida e destino barrado
  # pelo filtro SSRF sao configuracao, nao instabilidade. FileTooLarge e
  # UnsupportedContentType so podem ser levantados DEPOIS de um 2xx
  # (safe_fetch/fetcher.rb:35 corta o corpo em quem nao e Net::HTTPSuccess) —
  # ou seja, a entrega ja aconteceu; reentregar duplicaria o webhook.
  PERMANENT_ERRORS = [
    SafeFetch::InvalidUrlError,
    SafeFetch::UnsafeUrlError,
    SafeFetch::UnsupportedMethodError,
    SafeFetch::FileTooLargeError,
    SafeFetch::UnsupportedContentTypeError
  ].freeze

  # 408 e 429 sao o proprio destino pedindo "tente de novo"; 5xx e o destino
  # quebrado. Qualquer outro 4xx e o destino recusando o payload — cinco
  # tentativas so multiplicam a recusa.
  RETRYABLE_HTTP_STATUSES = [408, 429].freeze

  class RetryableError < StandardError
    attr_reader :status

    def initialize(status:, message:)
      @status = status
      super(message)
    end
  end

  # Identidade da entrega: o id que vai no cabecalho X-Chatwoot-Delivery e, quando existe,
  # o registro Webhook a que ela pertence. Sao um conceito so — o que se esta entregando e
  # para quem — e por isso viajam juntos em vez de como dois argumentos soltos.
  Delivery = Struct.new(:id, :webhook_id, keyword_init: true)

  def initialize(url, payload, webhook_type, secret: nil, delivery: nil)
    @url = url
    @payload = payload
    @webhook_type = webhook_type
    @secret = secret
    @delivery = delivery || Delivery.new
  end

  def self.execute(url, payload, webhook_type, secret: nil, delivery: nil)
    new(url, payload, webhook_type, secret: secret, delivery: delivery).execute
  end

  def execute
    perform_request
    # Bloco 4.14: o registro nasce AQUI, e nao numa camada acima, porque este e o unico
    # ponto que sabe o resultado real da requisicao. Ate o 1.13 a excecao morria dentro
    # deste metodo e o job terminava com sucesso — um log alimentado por "o job nao
    # explodiu" gravaria "entregue" para entrega que nunca aconteceu.
    record_delivery(:delivered)
  rescue StandardError => e
    record_delivery(:failed, e)
    raise RetryableError.new(status: http_status(e), message: e.message) if retryable_agent_bot_error?(e)
    # B3: sem este `raise` a excecao morria aqui e o job terminava com sucesso —
    # o webhook dizia que entregou sem ter entregado, e o `retry_on` do
    # WebhookJob nunca via nada para reentregar. Quem decide reentregar e o
    # ActiveJob; o efeito colateral (marcar mensagem falha / reabrir conversa)
    # fica para o esgotamento das tentativas, em WebhookJob#handle_exhaustion.
    raise e if retryable?(e)

    handle_failure(e)
  end

  def handle_failure(error)
    handle_error(error)
    Rails.logger.warn "Exception: Invalid webhook URL #{@url} : #{error.message}"
  end

  private

  def perform_request
    body = @payload.to_json
    SafeFetch.fetch(
      @url,
      method: :post,
      body: body,
      headers: request_headers(body),
      open_timeout: webhook_timeout,
      read_timeout: webhook_timeout,
      validate_content_type: false
    ) { |_response| nil }
  end

  def request_headers(body)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    headers['X-Chatwoot-Delivery'] = @delivery.id if @delivery.id.present?
    if @secret.present?
      ts = Time.now.to_i.to_s
      headers['X-Chatwoot-Timestamp'] = ts
      headers['X-Chatwoot-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @secret, "#{ts}.#{body}")}"
    end
    headers
  end

  def handle_error(error)
    return unless SUPPORTED_ERROR_HANDLE_EVENTS.include?(@payload[:event])
    return unless message

    case @webhook_type
    when :agent_bot_webhook
      update_conversation_status(message)
    when :api_inbox_webhook
      update_message_status(error)
    end
  end

  def update_conversation_status(message)
    conversation = message.conversation
    return unless conversation&.pending?
    return if conversation&.account&.keep_pending_on_bot_failure

    conversation.open!
    create_agent_bot_error_activity(conversation)
  end

  def create_agent_bot_error_activity(conversation)
    content = I18n.t('conversations.activity.agent_bot.error_moved_to_open')
    Conversations::ActivityMessageJob.perform_later(conversation.id, activity_message_params(conversation, content))
  end

  def activity_message_params(conversation, content)
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
  end

  def update_message_status(error)
    Messages::StatusUpdateService.new(message, 'failed', error.message).perform
  end

  def message
    return if message_id.blank?

    if defined?(@message)
      @message
    else
      @message = Message.find_by(id: message_id)
    end
  end

  def message_id
    @payload[:id]
  end

  def webhook_timeout
    raw_timeout = GlobalConfig.get_value('WEBHOOK_TIMEOUT')
    timeout = raw_timeout.presence&.to_i

    timeout&.positive? ? timeout : 5
  end

  # Registrar nao pode derrubar entrega: se a gravacao falhar, o webhook ja foi (ou ja
  # falhou) e o resultado disso nao muda por causa do log.
  def record_delivery(status, error = nil)
    return if @delivery.webhook_id.blank? || @delivery.id.blank?

    webhook = Webhook.find_by(id: @delivery.webhook_id)
    return if webhook.blank?

    webhook.webhook_deliveries
           .find_or_initialize_by(delivery_id: @delivery.id)
           .update!(delivery_attributes(webhook, status, error))
  rescue StandardError => e
    Rails.logger.warn("[webhook_delivery] nao registrou #{@delivery.id}: #{e.message}")
  end

  def delivery_attributes(webhook, status, error)
    {
      account_id: webhook.account_id,
      event: @payload[:event] || @payload['event'],
      payload: @payload,
      status: status,
      http_status: http_status(error),
      error_message: error&.message&.truncate(1000),
      delivered_at: (Time.zone.now if status == :delivered)
    }
  end

  def retryable_agent_bot_error?(error)
    @webhook_type == :agent_bot_webhook && RETRYABLE_AGENT_BOT_STATUSES.include?(http_status(error))
  end

  def retryable?(error)
    return false if PERMANENT_ERRORS.any? { |klass| error.is_a?(klass) }
    return retryable_http_status?(http_status(error)) if error.is_a?(SafeFetch::HttpError)

    # Timeout, socket, DNS, TLS: transitorio ate prova em contrario.
    true
  end

  def retryable_http_status?(status)
    return false if status.blank?

    RETRYABLE_HTTP_STATUSES.include?(status) || status >= 500
  end

  def http_status(error)
    return unless error.is_a?(SafeFetch::HttpError)

    error.message.to_s[/\A(\d{3})\b/, 1]&.to_i
  end
end
