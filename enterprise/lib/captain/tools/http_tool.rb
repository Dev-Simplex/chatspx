require 'agents'

class Captain::Tools::HttpTool < Agents::Tool
  # Trace de tool calls: o HttpTool NÃO herda de BasePublicTool, então ficava de fora do
  # recorder — as custom tools de todos os tenants não geravam trace nenhum, e o que não tem
  # trace não chega na nota do turno seguinte nem no eval. Prepend na própria classe cobre
  # também as subclasses anônimas que o Concerns::Toolable cria por slug.
  prepend Captain::Tools::TraceRecorder

  # Falha de consulta, classificada. O modelo precisa saber QUE classe de falha foi e, sobretudo,
  # que nenhuma delas é ausência de dado — senão completa de memória (auditoria de 20/09, §5:
  # timeout de 30s, HTTP≠2xx, DNS, SSRF e corpo >1MB colapsavam todos em
  # 'An error occurred while executing the request').
  class FalhaDeConsulta < StandardError
    attr_reader :classe

    def initialize(classe, detalhe = nil)
      @classe = classe
      super(detalhe.presence || classe.to_s)
    end
  end

  # Tom espelhado na Captain::Tools::BuscarUnidadesTool::FALHA, que é a referência certa no repo:
  # diz o que aconteceu, nomeia que é falha de consulta e fecha a porta pra resposta de memória.
  # Cada mensagem é autossuficiente porque o modelo pode ver só uma delas.
  NAO_INVENTE = 'Isto é falha de consulta, não ausência de dado: não conclua que o dado não ' \
                'existe, não responda de memória e não afirme nada sobre o que foi perguntado. ' \
                'Diga que não conseguiu consultar agora.'.freeze

  FALHAS = {
    timeout: 'A consulta não respondeu a tempo.',
    indisponivel: 'O sistema consultado não respondeu ou está fora do ar.',
    nao_autorizado: 'A consulta foi recusada pelo sistema consultado (credencial ou permissão).',
    resposta_invalida: 'O sistema consultado respondeu, mas a resposta não pôde ser lida.',
    corpo_excessivo: 'A resposta do sistema consultado é grande demais para ser lida aqui.'
  }.freeze

  # 2xx sem corpo utilizável. NÃO é `vazio_completo`: um 204 pode ser resposta válida de uma
  # ação e resposta inútil de uma consulta, e o HttpTool não sabe qual é qual — o contrato é por
  # operação e quem o conhece é quem cadastrou a tool. Declarar ausência aqui seria inventar
  # ausência, que é o defeito que este PR fecha.
  SEM_CONTEUDO = 'A consulta foi respondida, mas veio sem conteúdo. Isto NÃO confirma que o ' \
                 'dado não existe: não conclua ausência e não responda de memória.'.freeze

  def initialize(assistant, custom_tool)
    @assistant = assistant
    @custom_tool = custom_tool
    super()
  end

  def active?
    @custom_tool.enabled?
  end

  def perform(tool_context, **params)
    url = @custom_tool.build_request_url(params)
    body = @custom_tool.build_request_body(params)

    response = execute_http_request(url, body, tool_context)
    formatado = formatar(response)

    return Captain::Tools::Result.desconhecido(SEM_CONTEUDO, detalhe: "http #{response.code} sem corpo") if formatado.blank?

    Captain::Tools::Result.sucesso(formatado)
  rescue FalhaDeConsulta => e
    registrar_falha(e)
    Captain::Tools::Result.erro("#{FALHAS.fetch(e.classe)} #{NAO_INVENTE}", detalhe: "#{e.classe}: #{e.message}")
  rescue StandardError => e
    registrar_falha(e)
    Captain::Tools::Result.erro("#{FALHAS.fetch(:indisponivel)} #{NAO_INVENTE}", detalhe: "#{e.class}: #{e.message}")
  end

  # Additive helper for the custom-tool "test" endpoint (admin smoke test). Reuses the
  # same SSRF guard and request/auth building as #perform, but returns the raw HTTP
  # status/body instead of the LLM-formatted string. Does NOT alter #perform (the
  # LLM-facing entrypoint) — purely additive.
  def perform_test(**params)
    url = @custom_tool.build_request_url(params)
    body = @custom_tool.build_request_body(params)

    response = execute_http_request(url, body, nil)
    { ok: true, status: response.code.to_i, body: truncate_test_body(response.body) }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  private

  PRIVATE_IP_RANGES = [
    IPAddr.new('127.0.0.0/8'),    # IPv4 Loopback
    IPAddr.new('10.0.0.0/8'),     # IPv4 Private network
    IPAddr.new('172.16.0.0/12'),  # IPv4 Private network
    IPAddr.new('192.168.0.0/16'), # IPv4 Private network
    IPAddr.new('169.254.0.0/16'), # IPv4 Link-local
    IPAddr.new('::1'),            # IPv6 Loopback
    IPAddr.new('fc00::/7'),       # IPv6 Unique local addresses
    IPAddr.new('fe80::/10')       # IPv6 Link-local
  ].freeze

  # Limit response size to prevent memory exhaustion and match LLM token limits
  # 1MB of text ≈ 250K tokens, which exceeds most LLM context windows
  MAX_RESPONSE_SIZE = 1.megabyte

  TIMEOUTS = [Net::OpenTimeout, Net::ReadTimeout, Timeout::Error].freeze
  INDISPONIVEL = [SocketError, EOFError, Errno::ECONNREFUSED, Errno::ECONNRESET,
                  Errno::EHOSTUNREACH, Errno::ENETUNREACH, OpenSSL::SSL::SSLError].freeze

  # O detalhe técnico (URL, corpo, classe da exceção) fica no log e no `detalhe` do Result;
  # nunca no texto que o modelo lê. Slug identifica a tool sem expor credencial.
  def registrar_falha(erro)
    Rails.logger.error("HttpTool execution error for #{@custom_tool.slug}: #{erro.class} - #{erro.message}")
  end

  def formatar(response)
    @custom_tool.format_response(response.body)
  rescue StandardError => e
    # Template/parse do corpo: o servidor respondeu, quem não soube ler fomos nós.
    raise FalhaDeConsulta.new(:resposta_invalida, "format_response: #{e.class}: #{e.message}")
  end

  def execute_http_request(url, body, tool_context)
    uri = URI.parse(url)

    # Check if resolved IP is private
    check_private_ip!(uri.host)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10
    http.max_retries = 0 # Disable redirects

    request = build_http_request(uri, body)
    apply_authentication(request)
    apply_metadata_headers(request, tool_context)

    response = executar(http, request)

    raise FalhaDeConsulta.new(classe_do_status(response.code), "HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

    validate_response!(response)

    response
  end

  # Traduz a exceção de transporte na classe de falha correspondente, antes que o rescue
  # genérico do #perform a achate em "indisponível".
  def executar(http, request)
    http.request(request)
  rescue *TIMEOUTS => e
    raise FalhaDeConsulta.new(:timeout, "#{e.class}: #{e.message}")
  rescue *INDISPONIVEL => e
    raise FalhaDeConsulta.new(:indisponivel, "#{e.class}: #{e.message}")
  end

  # 401/403 é credencial — o operador precisa distinguir isso de "fora do ar" no trace.
  # 408/429/5xx é transitório do lado de lá. O resto (400, 404, 422...) é contrato: a chamada
  # chegou e foi rejeitada, e nenhum deles autoriza concluir que o dado não existe.
  def classe_do_status(codigo)
    numero = codigo.to_i
    return :nao_autorizado if [401, 403].include?(numero)
    return :indisponivel if numero == 408 || numero == 429 || numero >= 500

    :resposta_invalida
  end

  def check_private_ip!(hostname)
    ip_address = IPAddr.new(Resolv.getaddress(hostname))

    # SSRF bloqueado: o motivo real fica no log. Pro modelo é indisponibilidade — dizer "IP
    # privado" não o ajuda a atender e expõe topologia na conversa.
    raise FalhaDeConsulta.new(:indisponivel, 'blocked: hostname resolves to private IP address') if
      PRIVATE_IP_RANGES.any? { |range| range.include?(ip_address) }
  rescue Resolv::ResolvError, SocketError => e
    raise FalhaDeConsulta.new(:indisponivel, "DNS resolution failed: #{e.message}")
  end

  def validate_response!(response)
    content_length = response['content-length']&.to_i
    if content_length && content_length > MAX_RESPONSE_SIZE
      raise FalhaDeConsulta.new(:corpo_excessivo, "content-length #{content_length} > #{MAX_RESPONSE_SIZE}")
    end

    return unless response.body && response.body.bytesize > MAX_RESPONSE_SIZE

    raise FalhaDeConsulta.new(:corpo_excessivo, "body #{response.body.bytesize} > #{MAX_RESPONSE_SIZE}")
  end

  def build_http_request(uri, body)
    if @custom_tool.http_method == 'POST'
      request = Net::HTTP::Post.new(uri.request_uri)
      if body
        request.body = body
        request['Content-Type'] = 'application/json'
      end
    else
      request = Net::HTTP::Get.new(uri.request_uri)
    end
    request
  end

  def apply_authentication(request)
    headers = @custom_tool.build_auth_headers
    headers.each { |key, value| request[key] = value }

    credentials = @custom_tool.build_basic_auth_credentials
    request.basic_auth(*credentials) if credentials
  end

  def apply_metadata_headers(request, tool_context)
    state = tool_context&.state || {}
    metadata_headers = @custom_tool.build_metadata_headers(state)
    metadata_headers.each { |key, value| request[key] = value }
  end

  def truncate_test_body(raw)
    raw.to_s.dup.force_encoding(Encoding::UTF_8).scrub('?')[0, 5000]
  end
end
