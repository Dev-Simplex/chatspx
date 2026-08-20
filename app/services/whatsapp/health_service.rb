class Whatsapp::HealthService
  class ApiError < StandardError
    attr_reader :http_status, :code, :subcode

    def initialize(message:, http_status:, code: nil, subcode: nil)
      super(message)
      @http_status = http_status
      @code = code
      @subcode = subcode
    end

    def authorization_error?
      code.to_i == 190
    end
  end

  BASE_URI = 'https://graph.facebook.com'.freeze
  MINIMUM_HEALTH_API_VERSION = 24.0
  PERSISTED_FIELDS = %i[
    id
    display_phone_number
    verified_name
    name_status
    quality_rating
    messaging_limit_tier
    status
    account_mode
    code_verification_status
    throughput_level
    last_onboarded_time
    is_on_biz_app
    platform_type
    business_account_id
    business_account_name
    business_portfolio_id
    business_portfolio_name
  ].freeze
  RISKY_QUALITY_RATINGS = %w[YELLOW RED].freeze
  RISKY_STATUSES = %w[BANNED RESTRICTED RATE_LIMITED FLAGGED DISCONNECTED DELETED].freeze

  def initialize(channel)
    @channel = channel
    @access_token = channel.provider_config['api_key']
    # TODO: Remove this health-specific minimum when all WhatsApp integrations are consolidated on the latest Graph API version.
    configured_api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0').delete_prefix('v').to_f
    @api_version = "v#{[configured_api_version, MINIMUM_HEALTH_API_VERSION].max}"
  end

  def fetch_health_status
    validate_channel!

    phone_health_data = fetch_graph_data(@channel.provider_config['phone_number_id'], phone_health_fields)
    business_account_data = fetch_graph_data(@channel.provider_config['business_account_id'], business_account_fields)

    format_phone_health_response(phone_health_data).merge(format_business_account_response(business_account_data))
  end

  def sync_health_status!
    attempted_at = Time.current
    previous_health = @channel.phone_number_health
    health_status = fetch_health_status

    log_risky_transition(previous_health, health_status) if persist_health_status(health_status, attempted_at)

    health_status.merge(health_checked_at: attempted_at)
  rescue StandardError => e
    persist_health_error(e, attempted_at)
    raise
  end

  private

  def validate_channel!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'API key is missing' if @access_token.blank?
    raise ArgumentError, 'Phone number ID is missing' if @channel.provider_config['phone_number_id'].blank?
    raise ArgumentError, 'Business account ID is missing' if @channel.provider_config['business_account_id'].blank?
  end

  def fetch_graph_data(resource_id, fields)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{resource_id}",
      query: {
        fields: fields,
        access_token: @access_token
      }
    )

    handle_response(response)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error fetching health data: #{e.message}"
    raise
  end

  def phone_health_fields
    %w[
      id
      quality_rating
      whatsapp_business_manager_messaging_limit
      status
      code_verification_status
      account_mode
      display_phone_number
      name_status
      verified_name
      webhook_configuration
      throughput
      last_onboarded_time
      is_on_biz_app
      platform_type
      certificate
    ].join(',')
  end

  def business_account_fields
    %w[id name owner_business_info].join(',')
  end

  def handle_response(response)
    return response.parsed_response if response.success?

    parsed_response = response.parsed_response
    error_data = parsed_response.is_a?(Hash) ? parsed_response['error'].to_h : {}
    error = ApiError.new(
      message: error_data['message'].presence || 'WhatsApp API request failed',
      http_status: response.code,
      code: error_data['code'],
      subcode: error_data['error_subcode']
    )

    Rails.logger.error(
      "[WHATSAPP HEALTH] WhatsApp API request failed: http_status=#{error.http_status} " \
      "code=#{error.code} subcode=#{error.subcode} message=#{error.message}"
    )
    raise error
  end

  def format_phone_health_response(phone_response)
    {
      id: phone_response['id'],
      display_phone_number: phone_response['display_phone_number'],
      verified_name: phone_response['verified_name'],
      name_status: phone_response['name_status'],
      quality_rating: phone_response['quality_rating'],
      messaging_limit_tier: phone_response['whatsapp_business_manager_messaging_limit'],
      status: phone_response['status'],
      account_mode: phone_response['account_mode'],
      code_verification_status: phone_response['code_verification_status'],
      webhook_configuration: phone_response['webhook_configuration'],
      expected_webhook_url: build_expected_webhook_url,
      # RECONCILIACAO homologacao × v4.16.2 — UNIAO, e cada linha tem dono.
      #
      # `acceptable_webhook_urls` e da equipe e NAO PODE SAIR: a Meta aceita um unico
      # `override_callback_uri` por WABA, e com varios numeros no mesmo WABA a URL registrada
      # pertence a so um deles — mesmo sendo valida para todos, porque a entrada resolve o canal
      # pelo `phone_number_id` do payload. Sem este campo, `AccountHealth.vue` (que veio no
      # merge, com spec proprio) volta a acusar "webhook url mismatch" num canal que funciona.
      # Os metodos `build_acceptable_webhook_urls`/`sibling_phone_numbers` ja estao neste
      # arquivo: sem esta linha eles seriam codigo morto.
      acceptable_webhook_urls: build_acceptable_webhook_urls,
      throughput: phone_response['throughput'],
      # `throughput_level` e `is_on_biz_app` sao do upstream, e entram em PERSISTED_FIELDS.
      throughput_level: phone_response.dig('throughput', 'level'),
      last_onboarded_time: phone_response['last_onboarded_time'],
      is_on_biz_app: phone_response['is_on_biz_app'],
      platform_type: phone_response['platform_type'],
      # `certificate` e da equipe. Ele NAO esta em PERSISTED_FIELDS de proposito: o upstream
      # define ali o que fica gravado no canal, e acrescentar campo aquela lista muda o que a
      # frota inteira persiste — decisao que nao e desta reconciliacao. Ele volta a cada fetch.
      certificate: phone_response['certificate']
    }
  end

  # `business_id` da homologacao NAO foi trazido, e a razao e que ele deixou de ser necessario:
  # ele repetia `provider_config['business_account_id']`, e o upstream passou a buscar o dado na
  # FONTE (segunda chamada Graph, abaixo), entregando `business_account_id` mais
  # `business_account_name` e o portfolio. O `AccountHealth.vue` do merge ja le a forma nova
  # (`business_portfolio_id`). Nada se perdeu — o mesmo dado passou a ter nome melhor e vizinhos.
  def format_business_account_response(business_account_response)
    owner_business_info = business_account_response['owner_business_info'] || {}

    {
      business_account_id: business_account_response['id'],
      business_account_name: business_account_response['name'],
      business_portfolio_id: owner_business_info['id'],
      business_portfolio_name: owner_business_info['name']
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

  def persist_health_status(health_status, attempted_at)
    # Health polling must bypass credential validation, timestamps, inbox touches, and audit callbacks.
    # rubocop:disable Rails/SkipsModelValidations
    updated_rows = health_attempt_scope(attempted_at).update_all(
      phone_number_health: health_status.slice(*PERSISTED_FIELDS),
      phone_number_health_checked_at: attempted_at,
      phone_number_health_error: nil
    )
    # rubocop:enable Rails/SkipsModelValidations

    updated_rows == 1
  end

  def persist_health_error(error, attempted_at)
    return unless @channel&.persisted?

    # Recording a provider failure must not run the same provider validation or channel callbacks.
    # rubocop:disable Rails/SkipsModelValidations
    health_attempt_scope(attempted_at).update_all(
      phone_number_health_checked_at: attempted_at,
      phone_number_health_error: error.message.truncate(500)
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def health_attempt_scope(attempted_at)
    Channel::Whatsapp.where(id: @channel.id)
                     .where('phone_number_health_checked_at < ? OR phone_number_health_checked_at IS NULL', attempted_at)
  end

  def log_risky_transition(previous_health, health_status)
    return unless risky_health?(health_status)
    return if risk_signature(previous_health) == risk_signature(health_status)

    Rails.logger.warn(
      '[WHATSAPP HEALTH] risky_phone_number ' \
      "account_id=#{@channel.account_id} inbox_id=#{@channel.inbox&.id} channel_id=#{@channel.id} " \
      "phone_number_id=#{health_status[:id]} quality_rating=#{health_status[:quality_rating]} " \
      "status=#{health_status[:status]} messaging_limit_tier=#{health_status[:messaging_limit_tier]}"
    )
  end

  def risky_health?(health_status)
    RISKY_QUALITY_RATINGS.include?(health_status[:quality_rating]) || RISKY_STATUSES.include?(health_status[:status])
  end

  def risk_signature(health_status)
    health_status.to_h.with_indifferent_access.values_at(:quality_rating, :status)
  end
end
