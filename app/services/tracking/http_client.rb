# frozen_string_literal: true

# Bloco 5.11 — o cliente HTTP padrao dos destinos server-side.
#
# Ele e INJETAVEL de proposito (`Destinations::Base.new(..., http_client:)`): nenhum spec desta
# trilha toca a Meta, o GA4 ou o Google Ads de verdade. Teste que chama API de terceiro fica
# vermelho quando o terceiro tem incidente e verde quando o token expira — mede o mundo, nao o
# codigo.
#
# A traducao de falha de rede para `DeliveryError::Retryable` acontece AQUI, e nao em cada destino:
# `Errno::ECONNRESET` e uma falha do transporte, e o mesmo transporte serve os tres.
class Tracking::HttpClient
  TIMEOUT_SECONDS = 10

  NETWORK_ERRORS = [
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
    SocketError, Net::OpenTimeout, Net::ReadTimeout, EOFError
  ].freeze

  Response = Struct.new(:status, :body, keyword_init: true) do
    def success? = status.to_i.between?(200, 299)
  end

  def post_json(url, body:, query: {}, headers: {})
    response = HTTParty.post(
      url,
      body: body.to_json,
      query: query.presence,
      headers: { 'Content-Type' => 'application/json' }.merge(headers),
      timeout: TIMEOUT_SECONDS
    )

    Response.new(status: response.code, body: parsed(response))
  rescue *NETWORK_ERRORS => e
    raise Tracking::DeliveryError::Retryable.new("#{e.class.name}: #{e.message}", code: 'network_error')
  end

  private

  def parsed(response)
    response.parsed_response.is_a?(Hash) ? response.parsed_response : { 'raw' => response.body.to_s[0, 500] }
  rescue StandardError
    { 'raw' => response.body.to_s[0, 500] }
  end
end
