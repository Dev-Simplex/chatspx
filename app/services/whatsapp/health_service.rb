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
    build_webhook_url(@channel.phone_number)
  end

  def build_webhook_url(phone_number)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    return nil if frontend_url.blank?

    "#{frontend_url}/webhooks/whatsapp/#{phone_number}"
  end

  # A Meta aceita apenas UM override_callback_uri por WABA (POST /<WABA_ID>/subscribed_apps),
  # mas o Chatwoot registra nele a URL de um numero especifico. Com varios numeros no mesmo
  # WABA, a URL efetivamente registrada pertence a apenas um deles -- e mesmo assim e valida
  # para todos, porque o roteamento de entrada resolve o canal pelo phone_number_id do payload
  # e nao pela URL (ver Webhooks::WhatsappEventsJob#get_channel_from_wb_payload).
  # Sem isso, um dos numeros sempre acusaria "webhook url mismatch" mesmo funcionando.
  def build_acceptable_webhook_urls
    sibling_phone_numbers.filter_map { |phone_number| build_webhook_url(phone_number) }.uniq
  end

  def sibling_phone_numbers
    waba_id = @channel.provider_config['business_account_id']
    return [@channel.phone_number] if waba_id.blank?

    # Escopo restrito a mesma Account de proposito: um WABA pertence a um unico negocio, e
    # limitar a busca evita que a URL de outro tenant seja aceita como valida.
    siblings = Channel::Whatsapp.where(account_id: @channel.account_id, provider: 'whatsapp_cloud')
                                .where("provider_config->>'business_account_id' = ?", waba_id)
                                .pluck(:phone_number)

    (siblings + [@channel.phone_number]).compact.uniq
  end
end
