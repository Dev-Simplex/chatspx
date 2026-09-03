# frozen_string_literal: true

# Testa uma credencial de rastreio contra o provedor SEM gravar evento real. Bloco 5.02.
#
# "Sem gravar evento real" nao e um detalhe de implementacao — e o aceite. Uma verificacao que
# grava sujaria o relatorio de campanha do cliente com conversoes que nunca aconteceram, e o
# Smart Bidding aprenderia com elas. Por isso cada provedor usa o caminho de teste OFICIAL dele,
# e o servico se RECUSA a rodar quando esse caminho nao esta disponivel:
#
#  - **Meta**: `test_event_code` no payload manda o evento para o Test Events e o mantem fora da
#    producao. Sem o codigo, `verify` recusa em vez de mandar assim mesmo.
#  - **GA4**: o endpoint `/debug/mp/collect` valida o payload e devolve `validationMessages` sem
#    gravar nada. E o mesmo contrato do `/mp/collect`, no endereco que nao persiste.
#
# O cliente HTTP e INJETAVEL (`client:`) e por isso nenhum spec precisa de rede: o dublê responde
# no lugar do provedor. O default e HTTParty, que e o que o resto desta base ja usa.
class TrackingCredentials::Verifier
  PROVIDERS = %w[meta ga4].freeze
  META_API_VERSION = 'v21.0'
  META_ENDPOINT = "https://graph.facebook.com/#{META_API_VERSION}".freeze
  GA4_DEBUG_ENDPOINT = 'https://www.google-analytics.com/debug/mp/collect'
  TIMEOUT_IN_SECONDS = 10

  def initialize(credential, provider:, client: HTTParty)
    @credential = credential
    @provider = provider.to_s
    @client = client
  end

  def perform
    return failure(t('unknown_provider')) unless PROVIDERS.include?(@provider)

    result = @provider == 'meta' ? verify_meta : verify_ga4
    @credential.update(last_verified_at: Time.current) if result[:success]
    result
  rescue StandardError => e
    # Provedor fora do ar nao pode derrubar a tela de configuracao: vira resultado, nao excecao.
    failure(t('provider_unreachable', message: e.message))
  end

  private

  # A configuracao PUBLICA (Pixel ID, Measurement ID) mora no jsonb da inbox, escrito pelo bloco
  # 5.01. Ler com `dig` mantem este servico funcional antes de o 5.01 existir: o campo volta nil
  # e o operador recebe "configure o Pixel ID primeiro", em vez de um NoMethodError.
  def public_config
    @public_config ||= @credential.inbox.additional_attributes.to_h['widget_tracking'].to_h
  end

  def verify_meta
    pixel_id = public_config['meta_pixel_id']
    return failure(t('meta_missing_pixel_id')) if pixel_id.blank?
    return failure(t('meta_missing_access_token')) unless @credential.configured?(:meta_access_token)
    return failure(t('meta_missing_test_event_code')) if test_event_code.blank?

    response = @client.post("#{META_ENDPOINT}/#{pixel_id}/events", body: meta_payload, timeout: TIMEOUT_IN_SECONDS)
    read_meta_response(response)
  end

  def test_event_code
    @credential.meta_test_event_code
  end

  def meta_payload
    {
      access_token: @credential.meta_access_token,
      test_event_code: test_event_code,
      data: [{
        event_name: 'chatspx_verification',
        event_time: Time.current.to_i,
        action_source: 'website'
      }].to_json
    }
  end

  def read_meta_response(response)
    return success(t('meta_accepted')) if response.code == 200

    failure(dig_response(response, 'error', 'message') || t('meta_rejected'))
  end

  def verify_ga4
    measurement_id = public_config['ga4_measurement_id']
    return failure(t('ga4_missing_measurement_id')) if measurement_id.blank?
    return failure(t('ga4_missing_api_secret')) unless @credential.configured?(:ga4_api_secret)

    url = "#{GA4_DEBUG_ENDPOINT}?measurement_id=#{measurement_id}&api_secret=#{@credential.ga4_api_secret}"
    read_ga4_response(@client.post(url, body: ga4_payload.to_json, timeout: TIMEOUT_IN_SECONDS))
  end

  def ga4_payload
    { client_id: SecureRandom.uuid, events: [{ name: 'chatspx_verification', params: { engagement_time_msec: 1 } }] }
  end

  # O `/debug/mp/collect` responde 200 mesmo para payload invalido; quem diz se passou e a lista
  # `validationMessages`. Tratar o 200 como sucesso aqui seria aprovar credencial errada.
  def read_ga4_response(response)
    return failure(t('ga4_no_response')) unless response.code == 200

    messages = Array(dig_response(response, 'validationMessages'))
    return success(t('ga4_accepted')) if messages.empty?

    failure(messages.filter_map { |message| message['description'] }.join('; ').presence || t('ga4_rejected'))
  end

  def dig_response(response, *keys)
    body = response.respond_to?(:parsed_response) ? response.parsed_response : response.body
    body = JSON.parse(body) if body.is_a?(String)
    body.is_a?(Hash) ? body.dig(*keys) : nil
  rescue JSON::ParserError
    nil
  end

  def t(key, **args)
    I18n.t("errors.tracking_credential.verify.#{key}", **args)
  end

  def success(message)
    { success: true, provider: @provider, message: message }
  end

  def failure(message)
    { success: false, provider: @provider, message: message }
  end
end
