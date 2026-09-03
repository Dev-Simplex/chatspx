# frozen_string_literal: true

# Bloco 5.11 — T-C5.4: cliente da Conversions API da Meta.
#
#   POST https://graph.facebook.com/v21.0/<PIXEL_ID>/events?access_token=<TOKEN>
#
# O `access_token` viaja na QUERY porque e assim que a CAPI o aceita — e por isso ele nunca aparece
# no corpo, nunca entra no log de auditoria (que e derivado do corpo) e nunca sai do backend (RC10).
#
# Limites que a doc impoe e que este arquivo respeita: `event_time` de ate 7 dias para evento de
# site, ate 1.000 eventos por requisicao (mandamos 1 — o batch e o T-C5.10, que nao entra aqui).
class Tracking::Destinations::MetaCapi < Tracking::Destinations::Base
  API_VERSION = 'v21.0'
  GRAPH_HOST = 'https://graph.facebook.com'

  # A CAPI recusa evento de site com mais de 7 dias. Repetir nao melhora, entao vira `skipped` com
  # motivo, e nao uma retentativa que vai falhar cinco vezes e terminar na DLQ como se fosse erro.
  MAX_EVENT_AGE = 7.days

  # Os nomes padrao da Meta, que sao os que alimentam otimizacao de campanha. Evento fora do mapa vai
  # com o proprio nome `chatspx_*` (a CAPI aceita evento customizado) em vez de nao ir.
  STANDARD_EVENT_NAMES = {
    'chatspx_conversation_started' => 'Contact',
    'chatspx_prechat_submitted' => 'Lead',
    'chatspx_lead' => 'Lead',
    'chatspx_lead_qualified' => 'Lead',
    'chatspx_meeting_scheduled' => 'Schedule',
    'chatspx_deal_won' => 'Purchase'
  }.freeze

  # Campo de pessoa -> a normalizacao que precede o hash. A tabela existe para que ligar o modo com
  # PII seja UMA leitura: nao ha um caminho por campo escondido em oito linhas parecidas.
  PERSON_HASHERS = {
    'em' => :hashed_email,
    'ph' => :hashed_phone_digits,
    'fn' => :hashed_person_name,
    'ln' => :hashed_person_name,
    'ct' => :hashed_city,
    'st' => :hashed_region,
    'zp' => :hashed_postal_code,
    'country' => :hashed_country
  }.freeze

  def configured?
    settings.present? && settings.meta_capi_ready?
  end

  private

  def endpoint_url
    "#{GRAPH_HOST}/#{API_VERSION}/#{settings.meta_pixel_id}/events"
  end

  def query_params
    { access_token: settings.meta_access_token }
  end

  def skip_reason
    'event_too_old' if too_old?
  end

  def build_payload
    data = user_data
    return nil if data.blank?

    body = { data: [event_block(data)] }
    body[:test_event_code] = settings.meta_test_event_code if settings.meta_test_event_code.present?
    body
  end

  def event_block(data)
    {
      event_name: meta_event_name,
      # O instante do FATO, nunca o da entrega: a Meta usa `event_time` para atribuir ao clique.
      event_time: event.occurred_at.to_i,
      # O mesmo `event_id` que o navegador mandou — e o par que a Meta deduplica (5.13).
      event_id: event.event_id,
      action_source: 'website',
      event_source_url: visitor.event_source_url,
      user_data: data,
      custom_data: custom_data
    }.compact
  end

  def meta_event_name
    STANDARD_EVENT_NAMES.fetch(event.name, event.name)
  end

  # O CORACAO do modo sem PII (5.12). Enquanto `PiiPolicy.person_fields_allowed?` for falso — e ele e
  # falso por construcao — este metodo nao tem caminho nenhum que produza `em`, `ph`, `fn` ou `ln`.
  #
  # Nada aqui e hasheado alem do `external_id`: `fbp`, `fbc`, IP e user-agent vao CRUS por exigencia
  # da doc (T-C5.3). Hashear `fbp` e o jeito mais silencioso de zerar o match — a Meta recebe 200 e
  # descarta.
  def user_data
    identity = {
      external_id: Tracking::IdentityNormalizer.hashed_external_id(visitor.external_id),
      fbp: visitor.fbp,
      fbc: visitor.fbc,
      # IP e user-agent do VISITANTE. Ausentes quando a base nao os tem — nunca os do servidor.
      client_ip_address: visitor.ip,
      client_user_agent: visitor.user_agent
    }.compact

    identity.merge(person_user_data)
  end

  def person_user_data
    return {} unless Tracking::PiiPolicy.person_fields_allowed?

    PERSON_HASHERS.filter_map do |field, normalizer|
      value = Tracking::IdentityNormalizer.public_send(normalizer, person[field])
      [field.to_sym, value] if value.present?
    end.to_h
  end

  # `properties` ja e recusado pelo modelo quando traz `em`/`ph`/`fn`/`ln` crus, mas `ct`, `st`, `zp`
  # e `country` passam por la — e no payload da Meta essas quatro chaves SAO campos de pessoa. Sem
  # este filtro, bastaria alguem pos `ct: 'sao paulo'` em `properties` para o modo sem PII vazar por
  # uma porta que ninguem estava olhando.
  def custom_data
    props = event.properties.is_a?(Hash) ? event.properties : {}

    props.except(*Tracking::PiiPolicy::PERSON_FIELDS).compact.presence
  end

  def too_old?
    Time.current - event.occurred_at > MAX_EVENT_AGE
  end
end
