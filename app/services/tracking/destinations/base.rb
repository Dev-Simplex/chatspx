# frozen_string_literal: true

# Bloco 5.11 — o molde dos tres destinos server-side (Meta CAPI, GA4 Measurement Protocol, Google
# Ads Enhanced Conversions).
#
# O que e comum e mora aqui: o cliente HTTP injetavel, a traducao de status HTTP para as duas
# familias de erro (retentavel x permanente) e o log de auditoria derivado do payload REAL.
# O que e proprio de cada destino — URL, formato do corpo, vocabulario dos campos — fica na
# subclasse, porque e exatamente onde os tres discordam.
#
# `deliver!` nunca devolve "deu erro": ou devolve um `Result`, ou LEVANTA. Engolir a excecao e o
# defeito que o `webhook_job.rb:4` desta base ja documenta ter custado caro — o retry_on nao ve
# nada, o job termina com sucesso e o painel diz que entregou.
class Tracking::Destinations::Base
  Result = Struct.new(:status, :http_status, :field_names, :suppressed_field_names, :emq, :reason,
                      keyword_init: true)

  # 429 nao e erro do payload: e o destino pedindo calma. Vai para o backoff junto dos 5xx.
  RETRYABLE_STATUSES = [408, 429].freeze

  def initialize(event:, settings:, visitor: nil, person: nil, http_client: nil)
    @event = event
    @settings = settings
    @visitor = visitor || Tracking::VisitorContext.for(event)
    @person = person || Tracking::PersonData.new(event.contact)
    @http_client = http_client || Tracking::HttpClient.new
  end

  def configured?
    raise NotImplementedError
  end

  def deliver!
    reason = skip_reason
    return skipped(reason) if reason.present?

    payload = build_payload
    return skipped('no_identifier') if payload.blank?

    response = http_client.post_json(endpoint_url, body: payload, query: query_params, headers: request_headers)
    raise_for_status(response)

    sent(payload, response)
  end

  private

  attr_reader :event, :settings, :visitor, :person, :http_client

  def build_payload
    raise NotImplementedError
  end

  # Motivo pelo qual este destino nao deve nem tentar — limite do proprio destino (evento velho
  # demais para a CAPI, por exemplo). `skipped` e diferente de `failed`: nao ha o que retentar, e o
  # painel precisa mostrar POR QUE, e nao um erro que nunca houve.
  def skip_reason
    nil
  end

  def endpoint_url
    raise NotImplementedError
  end

  def query_params
    {}
  end

  def request_headers
    {}
  end

  # Nota de EMQ, quando o destino informa. Nenhum dos tres informa no corpo da resposta de escrita
  # hoje — fica `nil`, e o painel de 5.14 mostra ausencia em vez de inventar numero.
  def emq_from(_response)
    nil
  end

  # Os NOMES dos campos de pessoa que a base tinha e que o modo sem PII reteve. E a prova do aceite
  # do 5.12, e ela so vale porque e derivada do que EXISTIA, nao de uma lista fixa.
  def suppressed_field_names
    Tracking::PiiPolicy.suppressed_from(person.available_names)
  end

  def sent(payload, response)
    Result.new(status: :sent, http_status: response.status,
               field_names: Tracking::FieldNames.from(payload),
               suppressed_field_names: suppressed_field_names,
               emq: emq_from(response))
  end

  def skipped(reason)
    Result.new(status: :skipped, http_status: nil, field_names: [],
               suppressed_field_names: suppressed_field_names, emq: nil, reason: reason)
  end

  def raise_for_status(response)
    return if response.success?

    message = "#{self.class.name.demodulize}: HTTP #{response.status} #{response.body.to_json[0, 300]}"
    raise Tracking::DeliveryError::Retryable.new(message, http_status: response.status) if retryable_status?(response.status)

    raise Tracking::DeliveryError::Permanent.new(message, http_status: response.status)
  end

  def retryable_status?(status)
    status.to_i >= 500 || RETRYABLE_STATUSES.include?(status.to_i)
  end
end
