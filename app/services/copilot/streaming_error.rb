# Traduz a falha do provedor de LLM num codigo estavel do contrato SSE do copiloto.
#
# Regra de ouro: o cliente recebe SOMENTE o codigo e uma mensagem curta e generica.
# O corpo cru do provedor (que pode carregar id de organizacao, trecho do prompt ou
# ate a credencial) fica no log, e mesmo la passa por `redact`.
#
# O front decide o texto que o agente le a partir do `code`; um codigo desconhecido
# deve cair no texto generico do front, nunca quebrar a tela.
class Copilot::StreamingError < StandardError
  UNAUTHORIZED = 'unauthorized'.freeze
  RATE_LIMITED = 'rate_limited'.freeze
  TIMEOUT = 'timeout'.freeze
  PROVIDER_DOWN = 'provider_down'.freeze
  PAYMENT_REQUIRED = 'payment_required'.freeze
  BAD_REQUEST = 'bad_request'.freeze
  NOT_CONFIGURED = 'not_configured'.freeze
  INTERNAL = 'internal'.freeze

  # Mapeado por NOME de classe (string) de proposito: assim nao dependemos de a
  # constante do RubyLLM/Faraday ja estar carregada para classificar o erro.
  ERROR_CODES = {
    'RubyLLM::UnauthorizedError' => UNAUTHORIZED,
    'RubyLLM::ForbiddenError' => UNAUTHORIZED,
    'RubyLLM::RateLimitError' => RATE_LIMITED,
    'RubyLLM::PaymentRequiredError' => PAYMENT_REQUIRED,
    'RubyLLM::OverloadedError' => PROVIDER_DOWN,
    'RubyLLM::ServiceUnavailableError' => PROVIDER_DOWN,
    'RubyLLM::ServerError' => PROVIDER_DOWN,
    'RubyLLM::BadRequestError' => BAD_REQUEST,
    'RubyLLM::ModelNotFoundError' => NOT_CONFIGURED,
    'RubyLLM::ConfigurationError' => NOT_CONFIGURED,
    'Llm::Config::MissingAccountApiKeyError' => NOT_CONFIGURED,
    'Faraday::TimeoutError' => TIMEOUT,
    'Net::ReadTimeout' => TIMEOUT,
    'Net::OpenTimeout' => TIMEOUT,
    'Timeout::Error' => TIMEOUT,
    'Faraday::ConnectionFailed' => PROVIDER_DOWN,
    'Errno::ECONNREFUSED' => PROVIDER_DOWN,
    'SocketError' => PROVIDER_DOWN
  }.freeze

  MESSAGES = {
    UNAUTHORIZED => 'The AI provider rejected the credentials configured for this account.',
    RATE_LIMITED => 'The AI provider is rate limiting this account.',
    TIMEOUT => 'The AI provider did not answer in time.',
    PROVIDER_DOWN => 'The AI provider is unavailable.',
    PAYMENT_REQUIRED => 'The AI provider account has no credit available.',
    BAD_REQUEST => 'The AI provider rejected the request.',
    NOT_CONFIGURED => 'The AI provider is not configured for this account.',
    INTERNAL => 'The copilot could not generate an answer.'
  }.freeze

  # ARMADILHA REAL (verificada com emissor falso em 28/07/2026):
  # no caminho de STREAMING o RubyLLM 1.9.2 nao usa o status HTTP do provedor —
  # `Providers::OpenAI::Streaming#parse_streaming_error` rebaixa tudo que nao for
  # server_error/rate_limit para 400, entao um 401 de chave revogada chega aqui
  # como BadRequestError. Como 401 e justamente o estado mais provavel hoje, a
  # classificacao por classe sozinha mentiria para o agente. Quando o codigo por
  # classe e ambiguo, refinamos pelo texto do provedor (que continua sem sair
  # daqui).
  AMBIGUOUS_CODES = [BAD_REQUEST, INTERNAL].freeze

  PROVIDER_HINTS = [
    [/insufficient[_ ]quota|exceeded your current quota|billing hard limit/i, PAYMENT_REQUIRED],
    [/rate[_ ]limit|too many requests/i, RATE_LIMITED],
    [/incorrect api key|invalid api key|invalid_api_key|unauthorized|authentication|api key provided|account_deactivated/i,
     UNAUTHORIZED],
    [/timed out|timeout/i, TIMEOUT],
    [/overloaded|service unavailable|bad gateway|server had an error/i, PROVIDER_DOWN]
  ].freeze

  # Padroes de credencial que jamais podem sair no log.
  # O `*` entra na classe porque alguns provedores devolvem a chave ja
  # parcialmente mascarada (`sk-proj-****...-401`) — no log ela nao acrescenta
  # nada e so atrapalha a leitura.
  SECRET_PATTERNS = [
    /sk-[A-Za-z0-9_*\-]{6,}/,
    /Bearer\s+[A-Za-z0-9._\-]{8,}/i
  ].freeze

  LOGGED_MESSAGE_LIMIT = 300

  attr_reader :code, :cause_class, :cause_message

  class << self
    def from(exception)
      code = code_for(exception)
      new(code, cause_class: exception.class.name, cause_message: exception.message)
    end

    def code_for(exception)
      code = code_from_class(exception)
      return code unless AMBIGUOUS_CODES.include?(code)

      code_from_provider_text(exception.message) || code
    end

    def code_from_class(exception)
      exception.class.ancestors.each do |ancestor|
        known = ERROR_CODES[ancestor.name]
        return known if known
      end

      INTERNAL
    end

    def code_from_provider_text(text)
      PROVIDER_HINTS.each do |pattern, code|
        return code if text.to_s.match?(pattern)
      end

      nil
    end

    # Sanitiza qualquer texto vindo do provedor antes de ir para o log.
    def redact(text)
      redacted = text.to_s
      SECRET_PATTERNS.each { |pattern| redacted = redacted.gsub(pattern, '[REDACTED]') }
      redacted = redacted.tr("\n", ' ').squeeze(' ').strip
      redacted.length > LOGGED_MESSAGE_LIMIT ? "#{redacted[0, LOGGED_MESSAGE_LIMIT]}..." : redacted
    end
  end

  def initialize(code, cause_class: nil, cause_message: nil)
    @code = MESSAGES.key?(code.to_s) ? code.to_s : INTERNAL
    @cause_class = cause_class
    @cause_message = cause_message
    super(MESSAGES[@code])
  end

  # Payload do evento `error` do contrato C1. Nada aqui vem do provedor.
  def to_event
    { code: code, message: MESSAGES[code] }
  end

  def log_context
    "error_code=#{code} error_class=#{cause_class || self.class.name} " \
      "error_message=\"#{self.class.redact(cause_message)}\""
  end
end
