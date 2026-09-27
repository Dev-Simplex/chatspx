# Chamadas do fork para o Captador, feitas pelo painel da conversa (22 §1.3; contrato em
# docs/contratos/captador.md). Assina no mesmo formato da entrada, com o segredo do hook:
# "sha256=" + HMAC-SHA256 de "<ts>.<MÉTODO>.<path?query>.<corpo>", e diz QUEM pede em
# X-Chatspx-Usuario: o Captador aplica o papel dessa pessoa, e não o de um usuário de serviço.
#
# Timeout curto de propósito: se o Captador cair, a seção do painel avisa e o atendimento segue.
class Spx::Captador::Client
  TIMEOUT = 3
  BASE_PATH = '/integracao/chatspx/v1'.freeze
  NETWORK_ERRORS = [
    RestClient::Exceptions::Timeout, RestClient::ServerBrokeConnection, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
    Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError
  ].freeze

  class Unavailable < StandardError; end

  Response = Struct.new(:status, :body)

  def initialize(hook, user)
    @settings = hook.settings
    @user = user
  end

  def lead(conversation_id:, contact_id:)
    request(:get, "#{BASE_PATH}/leads?#{{ conversation_id: conversation_id, contact_id: contact_id }.to_query}")
  end

  def move(lead_id, etapa_id)
    request(:post, "#{BASE_PATH}/leads/#{ERB::Util.url_encode(lead_id)}/mover", { etapa_id: etapa_id }.to_json)
  end

  private

  def request(method, path_and_query, body = '')
    url = "#{@settings['captador_url'].to_s.chomp('/')}#{path_and_query}"
    response = RestClient::Request.execute(
      method: method, url: url, payload: body.presence, headers: headers(method, URI(url).request_uri, body),
      open_timeout: TIMEOUT, read_timeout: TIMEOUT
    )
    parse(response)
  rescue RestClient::ExceptionWithResponse => e
    raise Unavailable, e.message if e.response.nil?

    parse(e.response)
  rescue *NETWORK_ERRORS => e
    raise Unavailable, e.message
  end

  def headers(method, request_uri, body)
    timestamp = Time.now.to_i.to_s
    signed = [timestamp, method.to_s.upcase, request_uri, body].join('.')
    {
      content_type: :json, accept: :json,
      'X-Captador-Instancia' => @settings['instance_key'].to_s,
      'X-Chatspx-Usuario' => @user.id.to_s,
      'X-Captador-Timestamp' => timestamp,
      'X-Captador-Assinatura' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @settings['shared_secret'].to_s, signed)}"
    }
  end

  def parse(response)
    body = response.body.present? ? JSON.parse(response.body) : nil
    Response.new(response.code, body)
  rescue JSON::ParserError
    Response.new(response.code, nil)
  end
end
