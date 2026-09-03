# frozen_string_literal: true

# Bloco 5.11 — T-C5.5: cliente do Measurement Protocol do GA4.
#
#   POST https://www.google-analytics.com/mp/collect?measurement_id=G-XXXX&api_secret=<SECRET>
#
# Sucesso e 204 com corpo vazio — o MP NAO valida payload em producao e responde 2xx para lixo. Isso
# tem duas consequencias que este arquivo assume: (1) nao adianta esperar diagnostico da resposta,
# entao os limites sao respeitados AQUI; (2) `emq` fica `nil`, porque o destino nao informa nada.
#
# Limites da doc, todos aplicados abaixo: 25 eventos por requisicao (mandamos 1), 25 parametros por
# evento, corpo abaixo de 130 kB, e backdating de 72 h.
#
# O GA4 nao deduplica NADA (risco R11). Por isso a decisao de rota (T-C5.7) e do chamador — o
# navegador OU o Measurement Protocol, nunca os dois — e a guarda de janela do 5.13 e o que impede
# que uma fila entupida transforme uma conversao em duas.
class Tracking::Destinations::Ga4Mp < Tracking::Destinations::Base
  ENDPOINT = 'https://www.google-analytics.com/mp/collect'

  MAX_PARAMS_PER_EVENT = 25
  # Alem disto o GA4 ignora o carimbo e usa a hora da chegada; mandar assim mesmo produz um evento
  # datado errado, que e pior que um evento sem carimbo.
  MAX_BACKDATING = 72.hours

  def configured?
    settings.present? && settings.ga4_mp_ready?
  end

  private

  def endpoint_url
    ENDPOINT
  end

  def query_params
    { measurement_id: settings.ga4_measurement_id, api_secret: settings.ga4_api_secret }
  end

  # Sem `client_id` o MP recusa o evento. Ele e o unico campo realmente obrigatorio.
  def build_payload
    client_id = visitor.ga_client_id
    return nil if client_id.blank?

    payload = {
      client_id: client_id,
      # Id opaco e hasheado. O GA4 proibe PII em `user_id`, e um id de contato hasheado nao e PII.
      user_id: Tracking::IdentityNormalizer.hashed_external_id(visitor.external_id),
      non_personalized_ads: false,
      consent: consent_block,
      events: [{ name: event.name, params: event_params }]
    }.compact

    payload[:timestamp_micros] = (event.occurred_at.to_f * 1_000_000).to_i unless backdated_too_far?
    payload
  end

  # T-C7.4 — o bloco de consentimento viaja no payload. Enquanto o 5.19 (consentimento por conta) nao
  # existir, o valor e o default do GA4 para trafego de site proprio.
  def consent_block
    { ad_user_data: 'GRANTED', ad_personalization: 'GRANTED' }
  end

  def event_params
    base = {
      # Sem `engagement_time_msec` o GA4 nao conta a sessao; 1 ms e o minimo que a doc aceita.
      engagement_time_msec: 1,
      session_id: visitor.ga_session_id,
      # O mesmo `event_id` das outras pontas: o GA4 nao deduplica por ele, mas e por ele que a
      # auditoria do 5.14 cruza os tres destinos quando o cliente pergunta "o evento saiu?".
      event_id: event.event_id
    }.compact

    # `properties` nunca traz PII crua (o modelo recusa), e as quatro chaves de localidade sao
    # retiradas pelo mesmo motivo do destino da Meta: no vocabulario de anuncio elas SAO pessoa.
    extra = (event.properties.is_a?(Hash) ? event.properties : {}).except(*Tracking::PiiPolicy::PERSON_FIELDS)

    base.merge(extra.compact).first(MAX_PARAMS_PER_EVENT).to_h
  end

  def backdated_too_far?
    Time.current - event.occurred_at > MAX_BACKDATING
  end
end
