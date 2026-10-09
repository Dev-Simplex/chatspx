# frozen_string_literal: true

require 'resolv'

# Chat interno — prévia de link (título, descrição, imagem e domínio) lida do Open Graph da página.
# Roda só no job (InternalMessages::LinkPreviewJob). Proteções contra SSRF: só http/https, o nome é
# resolvido aqui e a conexão vai para o IP já conferido (sem nova consulta de DNS no meio), nenhum IP
# privado/loopback/link-local/reservado (inclusive em cada redirecionamento), tempo curto e no máximo
# 512 KB lidos. Qualquer falha devolve nil: a mensagem fica sem cartão, sem erro para ninguém.
class InternalMessages::LinkPreviewService
  TIMEOUT = 3
  TOTAL_TIMEOUT = 6
  MAX_BYTES = 512.kilobytes
  MAX_REDIRECTS = 3
  USER_AGENT = 'Mozilla/5.0 (compatible; ChatSPX-LinkPreview/1.0)'
  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
    198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  class AbortRead < StandardError; end

  def initialize(url)
    @url = url
  end

  def perform
    html, final_url = Timeout.timeout(TOTAL_TIMEOUT) { fetch(@url) }
    return if html.blank?

    parse(html, final_url)
  rescue StandardError => e
    Rails.logger.info("Internal chat link preview skipped for #{@url}: #{e.class}")
    nil
  end

  def self.blocked_ip?(ip)
    ip = IPAddr.new(ip.to_s)
    ip = ip.native if ip.ipv4_mapped? || ip.ipv4_compat?
    BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
  end

  private

  def fetch(url, redirects = 0)
    uri = URI.parse(url)
    ip = safe_ip(uri.host) if uri.is_a?(URI::HTTP) && uri.host.present?
    return if ip.nil?

    response, body = request(uri, ip)
    return follow(url, response['location'], redirects) if response.is_a?(Net::HTTPRedirection)

    [body, url] if response.is_a?(Net::HTTPSuccess) && html?(response)
  end

  # Cada salto passa de novo por todas as conferências (esquema, DNS, IP).
  def follow(url, location, redirects)
    return if location.blank? || redirects >= MAX_REDIRECTS

    fetch(URI.join(url, location).to_s, redirects + 1)
  end

  # Todos os endereços do nome precisam ser públicos; conecta no primeiro.
  def safe_ip(host)
    addresses = Resolv.getaddresses(host.delete_prefix('[').delete_suffix(']'))
    return if addresses.empty? || addresses.any? { |address| self.class.blocked_ip?(address) }

    addresses.min_by { |address| address.include?(':') ? 1 : 0 }
  end

  def request(uri, ip)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = ip
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = http.read_timeout = http.write_timeout = http.ssl_timeout = TIMEOUT
    response = nil
    body = +''
    begin
      http.start do
        get = Net::HTTP::Get.new(uri, 'User-Agent' => USER_AGENT, 'Accept' => 'text/html')
        http.request(get) do |res|
          response = res
          read_limited(res, body) if res.is_a?(Net::HTTPSuccess) && html?(res)
          # Interrompe sempre: o Net::HTTP leria o resto do corpo (arquivo grande) para reaproveitar a conexão.
          raise AbortRead
        end
      end
    rescue AbortRead
      nil
    end
    [response, body]
  end

  def read_limited(response, body)
    response.read_body do |chunk|
      body << chunk
      raise AbortRead if body.bytesize >= MAX_BYTES
    end
  end

  def html?(response)
    response['content-type'].to_s.include?('text/html')
  end

  def parse(html, final_url)
    doc = Nokogiri::HTML(html)
    title = meta(doc, 'og:title', 'twitter:title') || doc.at('title')&.text
    return if title.blank?

    {
      'url' => @url, 'title' => clean(title, 200),
      'description' => clean(meta(doc, 'og:description', 'description'), 300),
      'image' => image_url(meta(doc, 'og:image', 'twitter:image'), final_url),
      'site_name' => clean(meta(doc, 'og:site_name'), 80),
      'domain' => URI.parse(final_url).host.to_s.delete_prefix('www.')
    }.compact
  end

  # Primeiro meta (property= ou name=) com conteúdo, na ordem dos nomes pedidos.
  def meta(doc, *names)
    names.each do |name|
      content = (doc.at("meta[property='#{name}']") || doc.at("meta[name='#{name}']"))&.[]('content')
      return content if content.present?
    end
    nil
  end

  def clean(text, limit)
    text.to_s.squish.truncate(limit).presence
  end

  # Só imagem https (a tela é https: http viraria conteúdo misto).
  def image_url(src, base)
    return if src.blank?

    uri = URI.join(base, src.strip)
    uri.to_s if uri.is_a?(URI::HTTPS)
  rescue URI::Error
    nil
  end
end
