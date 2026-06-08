class Llm::AccountCredentialsResolver
  OPENAI_ENDPOINT_CONFIG = 'CAPTAIN_OPEN_AI_ENDPOINT'.freeze
  OPENAI_DEFAULT_ENDPOINT = LlmConstants::OPENAI_API_ENDPOINT.freeze

  PROVIDER_PREFIXES = {
    'claude' => 'anthropic',
    'gpt' => 'openai',
    'whisper' => 'openai',
    'text-embedding' => 'openai',
    'gemini' => 'gemini'
  }.freeze

  def initialize(account:)
    @account = account
  end

  def openai_api_key
    return if @account.blank?

    Captain::OpenaiHookService.new(account: @account).openai_api_key
  end

  def anthropic_api_key
    return if @account.blank?

    Captain::AnthropicHookService.new(account: @account).anthropic_api_key
  end

  def credentials_for_model(model_id)
    provider = provider_for_model(model_id)
    case provider
    when 'anthropic'
      { anthropic_api_key: anthropic_api_key }
    when 'openai'
      { openai_api_key: openai_api_key, openai_api_base: openai_api_base }
    else
      { openai_api_key: openai_api_key, openai_api_base: openai_api_base }
    end
  end

  def provider_for_model(model_id)
    PROVIDER_PREFIXES.each do |prefix, provider|
      return provider if model_id.to_s.start_with?(prefix)
    end
    'openai'
  end

  def openai_api_base
    configured_endpoint = InstallationConfig.find_by(name: OPENAI_ENDPOINT_CONFIG)&.value.presence || OPENAI_DEFAULT_ENDPOINT
    normalize_openai_endpoint(configured_endpoint)
  end

  private

  def normalize_openai_endpoint(endpoint)
    normalized_endpoint = endpoint.to_s.chomp('/')
    return normalized_endpoint unless normalized_endpoint.casecmp?(OPENAI_DEFAULT_ENDPOINT)

    "#{normalized_endpoint}/v1"
  end
end
