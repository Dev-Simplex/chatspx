# Chamadas do fork para o Captador, feitas pelo painel da conversa (22 §1.3; contrato em
# docs/contratos/captador.md). Assina no mesmo formato da entrada, com o segredo do hook:
# "sha256=" + HMAC-SHA256 de "<ts>.<MÉTODO>.<path?query>.<corpo>", e diz QUEM pede em
# X-Chatspx-Usuario: o Captador aplica o papel dessa pessoa, e não o de um usuário de serviço.
#
# O captador_url vem do hook, que um admin de conta preenche: sem conferir o destino, o servidor
# consultaria endereços internos (metadados da AWS, Redis, o próprio app) e o painel mostraria a
# resposta (SSRF). Por isso só https, na porta 443, para os hosts de CAPTADOR_HOSTS_PERMITIDOS, e
# pelo Flows::SafeHttpClient, que recusa IP interno, fixa o IP resolvido e não segue redirecionamento.
#
# Timeout curto de propósito: se o Captador cair, a seção do painel avisa e o atendimento segue.
class Spx::Captador::Client
  TIMEOUT = 3
  BASE_PATH = '/integracao/chatspx/v1'.freeze
  DEFAULT_HOSTS = 'captador.spx.ia.br'.freeze

  class Unavailable < StandardError; end

  Response = Struct.new(:status, :body)

  # Também usado pelo Spx::CaptadorListener antes de enfileirar os eventos.
  def self.allowed_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && uri.port == 443 && allowed_hosts.include?(uri.host.to_s.downcase)
  rescue URI::InvalidURIError
    false
  end

  def self.allowed_hosts
    ENV.fetch('CAPTADOR_HOSTS_PERMITIDOS', DEFAULT_HOSTS).split(',').map { |host| host.strip.downcase }.compact_blank
  end

  def initialize(hook, user)
    @shared_secret = hook.captador_shared_secret
    @settings = hook.settings
    @user = user
  end

  def lead(conversation_id:, contact_id:)
    request(:get, "#{BASE_PATH}/leads?#{{ conversation_id: conversation_id, contact_id: contact_id }.to_query}")
  end

  def health
    request(:get, "#{BASE_PATH}/saude")
  end

  def move(lead_id, etapa_id)
    request(:post, "#{BASE_PATH}/leads/#{ERB::Util.url_encode(lead_id)}/mover", { etapa_id: etapa_id }.to_json)
  end

  private

  def request(method, path_and_query, body = '')
    url = "#{@settings['captador_url'].to_s.chomp('/')}#{path_and_query}"
    raise Unavailable, "destino fora de CAPTADOR_HOSTS_PERMITIDOS: #{url}" unless self.class.allowed_url?(url)

    result = Flows::SafeHttpClient.new(method: method, url: url, headers: headers(method, URI(url).request_uri, body),
                                       body: body.presence, timeout: TIMEOUT).perform
    Response.new(result.status, parse(result.body))
  rescue Flows::StepSkip => e
    raise Unavailable, e.message
  end

  def headers(method, request_uri, body)
    timestamp = Time.now.to_i.to_s
    headers = {
      'Accept' => 'application/json',
      'X-Captador-Instancia' => @settings['instance_key'].to_s,
      'X-Chatspx-Usuario' => @user.id.to_s,
      'X-Captador-Timestamp' => timestamp
    }
    headers['X-Captador-Assinatura'] = signature(method, request_uri, body, headers)
    headers
  end

  def signature(method, request_uri, body, headers)
    unless ActiveModel::Type::Boolean.new.cast(ENV.fetch('CAPTADOR_ASSINATURA_V2', false))
      signed = [headers['X-Captador-Timestamp'], method.to_s.upcase, request_uri, body].join('.')
      return "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @shared_secret.to_s, signed)}"
    end

    Spx::Captador::Signature.v2(
      secret: @shared_secret,
      timestamp: headers['X-Captador-Timestamp'],
      method: method,
      path: request_uri,
      identifier: headers['X-Captador-Instancia'],
      header_name: 'x-chatspx-usuario',
      header_value: headers['X-Chatspx-Usuario'],
      body: body
    )
  end

  def parse(body)
    body.present? ? JSON.parse(body) : nil
  rescue JSON::ParserError
    nil
  end
end
