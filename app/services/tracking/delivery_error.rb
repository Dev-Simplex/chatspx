# frozen_string_literal: true

# Bloco 5.11 — a raiz das DUAS falhas de entrega. As subclasses moram em `delivery_error/`:
#
#   Retryable  -> 5xx, 429, timeout, DNS. O destino esta fora do ar ou pediu calma; repetir com
#                 backoff resolve, e e o unico caso em que repetir faz sentido.
#   Permanent  -> 4xx que nao 429: token invalido, pixel inexistente, payload recusado. Repetir cinco
#                 vezes com backoff so atrasa em uma hora a mesma resposta e enche o log — vai direto
#                 para a DLQ, onde alguem consegue VER que a credencial esta errada.
#
# Confundir as duas e como o erro de credencial vira "instabilidade do destino" no relatorio.
class Tracking::DeliveryError < StandardError
  attr_reader :http_status, :code

  def initialize(message = nil, http_status: nil, code: nil)
    @http_status = http_status
    @code = code || (http_status ? "http_#{http_status}" : 'unknown')
    super(message || @code)
  end
end
