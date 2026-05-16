class Captain::AnthropicHookService
  class ApiKeyValidationError < StandardError; end
  class InvalidApiKeyError < ApiKeyValidationError; end
  class ApiConnectionError < ApiKeyValidationError; end

  APP_ID = 'anthropic'.freeze
  PROVIDER = 'anthropic'.freeze
  ANTHROPIC_API_BASE = 'https://api.anthropic.com'.freeze
  VALIDATION_OPEN_TIMEOUT_SECONDS = 5
  VALIDATION_TIMEOUT_SECONDS = 10

  def initialize(account:)
    @account = account
  end

  def connection_payload
    api_key = anthropic_api_key

    {
      provider: PROVIDER,
      configured: api_key.present?,
      masked_api_key: mask_api_key(api_key),
      updated_at: anthropic_hook&.updated_at
    }
  end

  def anthropic_api_key
    anthropic_hook&.settings&.dig('api_key').to_s.presence
  end

  def configured?
    anthropic_api_key.present?
  end

  def upsert_api_key!(api_key)
    raise ArgumentError, 'anthropic_api_key is required' if api_key.blank?

    hook = anthropic_hook || build_anthropic_hook
    hook.update!(settings: merged_settings(hook, api_key))
    @anthropic_hook = hook
  end

  def validate_and_upsert_api_key!(api_key)
    validate_api_key!(api_key)
    upsert_api_key!(api_key)
  end

  def validate_api_key!(api_key)
    raise ArgumentError, 'anthropic_api_key is required' if api_key.blank?

    response = validation_connection.get('v1/models') do |request|
      request.headers['x-api-key'] = api_key
      request.headers['anthropic-version'] = '2023-06-01'
      request.headers['Content-Type'] = 'application/json'
    end

    return true if response.success?

    handle_validation_failure(response)
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::Error => e
    Rails.logger.warn("#{self.class.name} API key validation failed due to network error: #{e.class} #{e.message}")
    raise ApiConnectionError, I18n.t('captain.errors.api_key_validation_failed')
  end

  def remove_api_key!
    return if anthropic_hook.blank?

    anthropic_hook.destroy!
    @anthropic_hook = nil
  end

  private

  attr_reader :account

  def validation_connection
    Faraday.new(url: ANTHROPIC_API_BASE) do |faraday|
      faraday.options.open_timeout = VALIDATION_OPEN_TIMEOUT_SECONDS
      faraday.options.timeout = VALIDATION_TIMEOUT_SECONDS
      faraday.adapter Faraday.default_adapter
    end
  end

  def handle_validation_failure(response)
    status = response.status.to_i
    raise InvalidApiKeyError, I18n.t('captain.errors.invalid_api_key') if [401, 403].include?(status)

    Rails.logger.warn(
      "#{self.class.name} API key validation unexpected response status=#{status} body=#{response.body.to_s.tr("\n", ' ')[0, 500]}"
    )
    raise ApiConnectionError, I18n.t('captain.errors.api_key_validation_failed')
  end

  def anthropic_hook
    @anthropic_hook ||= account.hooks.find_by(app_id: APP_ID)
  end

  def build_anthropic_hook
    account.hooks.new(
      app_id: APP_ID,
      hook_type: 'account',
      status: 'enabled',
      settings: {}
    )
  end

  def merged_settings(hook, api_key)
    current_settings = hook.settings || {}
    current_settings.merge('api_key' => api_key)
  end

  def mask_api_key(api_key)
    return nil if api_key.blank?
    return '*' * api_key.length if api_key.length <= 8

    "#{api_key[0..3]}#{'*' * (api_key.length - 8)}#{api_key[-4..]}"
  end
end
