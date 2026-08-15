class Whatsapp::HealthService
  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(channel)
    @channel = channel
    @access_token = channel.provider_config['api_key']
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def fetch_health_status
    validate_channel!
    fetch_phone_health_data
  end

  private

  def validate_channel!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'API key is missing' if @access_token.blank?
    raise ArgumentError, 'Phone number ID is missing' if @channel.provider_config['phone_number_id'].blank?
  end

  def fetch_phone_health_data
    phone_number_id = @channel.provider_config['phone_number_id']

    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      query: {
        fields: health_fields,
        access_token: @access_token
      }
    )

    handle_response(response)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error fetching health data: #{e.message}"
    raise e
  end

  def health_fields
    %w[
      id
      quality_rating
      messaging_limit_tier
      code_verification_status
      account_mode
      display_phone_number
      name_status
      verified_name
      webhook_configuration
      throughput
      last_onboarded_time
      platform_type
      certificate
    ].join(',')
  end

  def handle_response(response)
    unless response.success?
      error_message = "WhatsApp API request failed: #{response.code} - #{response.body}"
      Rails.logger.error "[WHATSAPP HEALTH] #{error_message}"
      raise error_message
    end

    data = response.parsed_response
    format_health_response(data)
  end

  def format_health_response(response)
    {
      id: response['id'],
      display_phone_number: response['display_phone_number'],
      verified_name: response['verified_name'],
      name_status: response['name_status'],
      quality_rating: response['quality_rating'],
      messaging_limit_tier: response['messaging_limit_tier'],
      account_mode: response['account_mode'],
      code_verification_status: response['code_verification_status'],
      webhook_configuration: response['webhook_configuration'],
      expected_webhook_url: build_expected_webhook_url,
      acceptable_webhook_urls: build_acceptable_webhook_urls,
      throughput: response['throughput'],
      last_onboarded_time: response['last_onboarded_time'],
      platform_type: response['platform_type'],
      certificate: response['certificate'],
      business_id: @channel.provider_config['business_account_id']
    }
  end

  def build_expected_webhook_url
    return nil if frontend_url.blank?

    webhook_url_for(@channel)
  end

  # A Meta so aceita um `override_callback_uri` por WABA
  # (POST /<WABA_ID>/subscribed_apps, ver Whatsapp::FacebookApiClient#override_waba_callback),
  # mas o Chatwoot registra nele uma URL por numero (Whatsapp::WebhookSetupService#build_callback_url).
  # Com dois numeros no mesmo WABA so uma das URLs pode estar registrada -- e a outra inbox
  # acusaria incompatibilidade mesmo funcionando, porque o roteamento de entrada resolve a inbox
  # pelo payload (Webhooks::WhatsappEventsJob#get_channel_from_wb_payload), nunca pela URL.
  # Por isso a URL de qualquer canal irmao do mesmo WABA e igualmente valida.
  #
  # Lista vazia significa "nao foi possivel determinar" (FRONTEND_URL ausente); nesse caso o
  # consumidor deve cair no comportamento antigo de comparar com expected_webhook_url.
  def build_acceptable_webhook_urls
    own_url = build_expected_webhook_url
    return [] if own_url.blank?

    ([own_url] + sibling_webhook_urls).uniq
  end

  def sibling_webhook_urls
    waba_id = @channel.provider_config['business_account_id']
    return [] if waba_id.blank?

    sibling_channels(waba_id).map { |channel| webhook_url_for(channel) }
  end

  # Escopo deliberadamente restrito a mesma conta: `business_account_id` e um campo livre dentro
  # de provider_config (sem validacao nem unicidade), entao uma busca global deixaria um canal de
  # outro tenant declarar o mesmo WABA e suprimir o alerta legitimo de URL incorreta desta conta.
  # Um WABA pertence a um unico negocio, logo na pratica os irmaos estao sempre na mesma conta.
  def sibling_channels(waba_id)
    Channel::Whatsapp
      .where(account_id: @channel.account_id, provider: 'whatsapp_cloud')
      .where("provider_config->>'business_account_id' = ?", waba_id)
      .order(:id)
  end

  def webhook_url_for(channel)
    "#{frontend_url}/webhooks/whatsapp/#{channel.phone_number}"
  end

  def frontend_url
    ENV.fetch('FRONTEND_URL', nil)
  end
end
