# frozen_string_literal: true

require 'net/http'
require 'ipaddr'
require 'resolv'

# Cliente HTTP(S) SSRF-safe para o nó `http_request` do motor Flow (usado por Flows::HttpAction).
# Recebe method/url/headers/body JÁ com Liquid resolvido e devolve um Result(status, body) OU
# levanta Flows::StepSkip (guarda intencional → passo `skipped` triável, sem Sentry).
#
# ── MODELO DE AMEAÇA (SSRF) ────────────────────────────────────────────────────────────────
# A URL pode ser INFLUENCIADA por dados semi-confiáveis (Liquid de atributos do contato). Sem
# defesa, o flow poderia bater em serviços internos (Redis/DB, o metadata da cloud em
# 169.254.169.254, o próprio app em localhost) — SSRF clássico. Defesas, em ordem:
#   1. Só http/https (StepSkip 'invalid_url').
#   2. Resolvo o host e RECUSO se QUALQUER IP resolvido for privado/loopback/link-local/CGNAT/
#      multicast/metadata (StepSkip 'ssrf_blocked'). IPv4-mapped é desembrulhado antes.
#   3. ANTI-DNS-REBINDING (TOCTOU): fixo a conexão no IP já validado (Net::HTTP#ipaddr=),
#      mantendo o hostname para SNI/verificação de certificado.
#   4. NÃO sigo redirect: 3xx volta verbatim (Net::HTTP não segue por padrão) → Location para
#      IP interno nunca é buscado.
#   5. Timeout curto (open+read) + cap de resposta (stream cortado) → sem DoS por host lento/
#      corpo gigante.
#   6. Headers hop-by-hop/sensíveis do usuário (Host/Content-Length/Connection/Transfer-Encoding)
#      são descartados por Flows::HttpAction antes de chegar aqui.
class Flows::SafeHttpClient
  Result = Struct.new(:status, :body)

  ALLOWED_SCHEMES = %w[http https].freeze
  METHOD_CLASSES = {
    'get' => Net::HTTP::Get, 'post' => Net::HTTP::Post, 'put' => Net::HTTP::Put,
    'patch' => Net::HTTP::Patch, 'delete' => Net::HTTP::Delete
  }.freeze

  # Faixas bloqueadas (SSRF). IPv4: RFC1918, loopback, link-local (inclui metadata .169.254),
  # CGNAT, this-host, TEST-NET, benchmarking, multicast, reservado. IPv6: loopback/unspecified,
  # NAT64, discard, doc, ULA, link-local, multicast.
  BLOCKED_IPV4 = ['0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
                  '172.16.0.0/12', '192.0.0.0/24', '192.0.2.0/24', '192.88.99.0/24', '192.168.0.0/16',
                  '198.18.0.0/15', '198.51.100.0/24', '203.0.113.0/24', '224.0.0.0/4', '240.0.0.0/4'].map { |c| IPAddr.new(c) }.freeze
  BLOCKED_IPV6 = ['::1/128', '::/128', '64:ff9b::/96', '100::/64', '2001:db8::/32',
                  'fc00::/7', 'fe80::/10', 'ff00::/8'].map { |c| IPAddr.new(c) }.freeze

  NETWORK_ERRORS = [Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
                    Errno::ENETUNREACH, Errno::ETIMEDOUT, SocketError, OpenSSL::SSL::SSLError,
                    IOError, EOFError].freeze

  HTTP_TIMEOUT = 5 # s, open+read — curto: um nó não pode pendurar o walker
  MAX_RESPONSE_BYTES = 64 * 1024 # teto do corpo lido/gravado

  def initialize(method:, url:, headers: {}, body: nil)
    @method = METHOD_CLASSES.key?(method.to_s) ? method.to_s : 'get'
    @url = url
    @headers = headers || {}
    @body = body
  end

  def perform
    uri = validated_uri
    dispatch(uri, validated_ip(uri))
  rescue *NETWORK_ERRORS => e
    raise Flows::StepSkip.new('http_error', "#{e.class}: #{e.message}")
  end

  private

  def validated_uri
    uri = URI.parse(@url)
    raise Flows::StepSkip.new('invalid_url', 'URL scheme must be http or https') unless ALLOWED_SCHEMES.include?(uri.scheme)
    raise Flows::StepSkip.new('invalid_url', 'URL host is missing') if uri.hostname.blank?

    uri
  rescue URI::InvalidURIError
    raise Flows::StepSkip.new('invalid_url', 'URL is malformed')
  end

  # Resolve o host e recusa se QUALQUER IP resolvido for interno. Devolve o 1º IP validado — a
  # conexão é fixada nele (anti-rebinding).
  def validated_ip(uri)
    ips = resolve_host_ips(uri.hostname)
    raise Flows::StepSkip.new('ssrf_blocked', "could not resolve host #{uri.hostname}") if ips.blank?

    ips.each do |ip|
      raise Flows::StepSkip.new('ssrf_blocked', "#{uri.hostname} resolves to a blocked address (#{ip})") if blocked_ip?(ip)
    end
    ips.first
  end

  # IP literal → usa direto (sem DNS; pega metadata/loopback por IP). Senão resolve A/AAAA.
  # Sobrescrevível nos specs p/ não bater em DNS real. Nunca levanta.
  def resolve_host_ips(host)
    return [host] if literal_ip?(host)

    Resolv.getaddresses(host)
  rescue StandardError
    []
  end

  def literal_ip?(host)
    IPAddr.new(host) && true
  rescue IPAddr::InvalidAddressError
    false
  end

  def blocked_ip?(ip_string)
    addr = IPAddr.new(ip_string.to_s).native # desembrulha IPv4-mapped → IPv4
    (addr.ipv4? ? BLOCKED_IPV4 : BLOCKED_IPV6).any? { |range| range.include?(addr) }
  rescue IPAddr::Error
    true # fail closed
  end

  def dispatch(uri, ip)
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.ipaddr = ip # fixa no IP validado (anti-rebinding), mantém hostname p/ SNI/cert
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = HTTP_TIMEOUT
    http.read_timeout = HTTP_TIMEOUT
    http.max_retries = 0
    read_capped(http, build_request(uri))
  end

  def build_request(uri)
    request = METHOD_CLASSES.fetch(@method).new(uri.request_uri)
    @headers.each { |key, value| request[key] = value }
    if @body.present?
      request.body = @body
      request['Content-Type'] ||= 'application/json'
    end
    request
  end

  # Lê a resposta em stream, mantendo o buffer SEMPRE ≤ MAX_RESPONSE_BYTES (só anexo o que cabe
  # no que resta do cap). Protege memória sem depender de cortar o socket no meio (a transferência
  # já é limitada pelo timeout). WebMock entrega o corpo stubado pelo mesmo caminho.
  def read_capped(http, request)
    status = nil
    body = +''
    http.start do |conn|
      conn.request(request) do |response|
        status = response.code.to_i
        response.read_body { |chunk| append_capped(body, chunk) }
      end
    end
    Result.new(status, body)
  end

  def append_capped(body, chunk)
    remaining = MAX_RESPONSE_BYTES - body.bytesize
    return if remaining <= 0

    body << (chunk.bytesize > remaining ? chunk.byteslice(0, remaining) : chunk)
  end
end
