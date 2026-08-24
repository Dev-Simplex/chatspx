# frozen_string_literal: true

# Duble do cliente HTTP dos destinos server-side (blocos 5.11/5.12/5.13).
#
# NAO e um spec: mora aqui para que os quatro arquivos de spec desta trilha usem O MESMO duble, e
# nao tres versoes que divergem. O rspec so carrega `*_spec.rb`, entao este arquivo entra por
# `require_relative` e nunca sozinho.
#
# Ele GUARDA as chamadas em vez de so responder, porque o aceite do 5.12 nao e sobre o que o cliente
# devolve — e sobre o que o corpo enviado contem e nao contem.
class FakeHttpClient
  attr_reader :calls

  def initialize(status: 200, body: { 'ok' => true }, raise_error: nil)
    @status = status
    @body = body
    @raise_error = raise_error
    @calls = []
  end

  def post_json(url, body:, query: {}, headers: {})
    @calls << { url: url, body: body, query: query, headers: headers }
    raise @raise_error if @raise_error

    Tracking::HttpClient::Response.new(status: @status, body: @body)
  end

  def called?
    calls.any?
  end

  def last_body
    calls.last&.fetch(:body)
  end

  # O corpo serializado como ele viaja no fio. E o unico jeito honesto de perguntar "o e-mail do
  # visitante saiu?": procurar a chave nao acha o valor escondido dentro de uma string aninhada.
  def last_body_json
    last_body.to_json
  end
end
