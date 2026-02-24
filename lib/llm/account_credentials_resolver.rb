class Llm::AccountCredentialsResolver
  OPENAI_ENDPOINT_CONFIG = 'CAPTAIN_OPEN_AI_ENDPOINT'.freeze
  OPENAI_DEFAULT_ENDPOINT = LlmConstants::OPENAI_API_ENDPOINT.freeze

  def initialize(account:)
    @account = account
  end

  def openai_api_key
    return if @account.blank?

    Captain::OpenaiHookService.new(account: @account).openai_api_key
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
