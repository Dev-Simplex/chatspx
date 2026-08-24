# frozen_string_literal: true

# Bloco 5.11 — T-C5.6: Enhanced Conversions for Leads da Google Ads API.
#
#   POST https://googleads.googleapis.com/v18/customers/<CID>:uploadClickConversions
#
# Aqui o modo sem PII tem uma consequencia que precisa estar escrita, porque ela e uma AUSENCIA e
# ausencia nao aparece em log: "Enhanced Conversions **for Leads**" e, por definicao, a conversao
# casada por dado de pessoa hasheado. Sem o DPA, esse casamento nao acontece — o que sobra e a
# conversao por `gclid`, que e o upload de click conversion classico e continua valendo muito
# (fecha o ciclo do lance para quem veio de anuncio).
#
# Entao: sem `gclid`, nao ha o que mandar, e a entrega vira `skipped` com motivo — nunca um payload
# vazio que a API aceita e ninguem consegue explicar depois.
class Tracking::Destinations::GoogleAds < Tracking::Destinations::Base
  API_VERSION = 'v18'
  API_HOST = 'https://googleads.googleapis.com'

  def configured?
    settings.present? && settings.google_ads_ready?
  end

  private

  def endpoint_url
    "#{API_HOST}/#{API_VERSION}/customers/#{settings.google_ads_customer_id}:uploadClickConversions"
  end

  def request_headers
    headers = {
      'Authorization' => "Bearer #{settings.google_ads_access_token}",
      'developer-token' => settings.google_ads_developer_token
    }
    headers['login-customer-id'] = settings.google_ads_login_customer_id if settings.google_ads_login_customer_id.present?
    headers
  end

  def skip_reason
    'no_identifier' if visitor.gclid.blank? && user_identifiers.blank?
  end

  def build_payload
    conversion = {
      conversionAction: "customers/#{settings.google_ads_customer_id}/conversionActions/#{settings.google_ads_conversion_action_id}",
      conversionDateTime: conversion_date_time,
      gclid: visitor.gclid,
      # `orderId` e o `event_id`: e o que faz o reenvio do mesmo fato NAO virar duas conversoes.
      orderId: event.event_id,
      conversionValue: properties['value'],
      currencyCode: properties['currency'],
      userIdentifiers: user_identifiers.presence
    }.compact

    # `partialFailure` para que um item recusado nao derrube o lote inteiro quando o batch de
    # T-C5.10 chegar.
    { conversions: [conversion], partialFailure: true }
  end

  # Vazio enquanto `PiiPolicy.person_fields_allowed?` for falso — que e sempre, hoje. E aqui que o
  # `hashedEmail`/`hashedPhoneNumber` entrariam, com E.164 no telefone (T-C5.6) e as chaves de
  # endereco SEM hash, que e a regra que difere da Meta.
  def user_identifiers
    return [] unless Tracking::PiiPolicy.person_fields_allowed?

    [
      identifier(:hashedEmail, Tracking::IdentityNormalizer.hashed_email(person['em'])),
      identifier(:hashedPhoneNumber, Tracking::IdentityNormalizer.hashed_phone_e164(person['ph'])),
      address_identifier
    ].compact
  end

  def identifier(key, value)
    return nil if value.blank?

    { key => value }
  end

  def address_identifier
    info = {
      hashedFirstName: Tracking::IdentityNormalizer.hashed_person_name(person['fn']),
      hashedLastName: Tracking::IdentityNormalizer.hashed_person_name(person['ln']),
      # Sem hash, por exigencia da API — e a diferenca que faz o payload da Meta e o do Google nao
      # poderem ser o mesmo objeto.
      city: Tracking::IdentityNormalizer.city(person['ct']),
      state: Tracking::IdentityNormalizer.region(person['st']),
      postalCode: Tracking::IdentityNormalizer.postal_code(person['zp']),
      countryCode: Tracking::IdentityNormalizer.country(person['country'])
    }.compact

    info.present? ? { addressInfo: info } : nil
  end

  # A API exige "yyyy-mm-dd hh:mm:ss+|-hh:mm", com o fuso explicito.
  def conversion_date_time
    event.occurred_at.strftime('%Y-%m-%d %H:%M:%S%:z')
  end

  def properties
    event.properties.is_a?(Hash) ? event.properties : {}
  end
end
