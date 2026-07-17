# frozen_string_literal: true

# DEPRECATED: This class uses the legacy OpenAI Ruby gem directly.
# Only used for PDF/file operations that require OpenAI's files API:
# - Captain::Llm::PdfProcessingService (files.upload for assistants)
# - Captain::Llm::PaginatedFaqGeneratorService (uses file_id from uploaded files)
#
# For all other LLM operations, use Llm::BaseAiService with RubyLLM instead.
class Llm::LegacyBaseOpenAiService
  DEFAULT_MODEL = 'gpt-4.1-mini'

  attr_reader :client, :model

  def initialize
    @client = OpenAI::Client.new(
      access_token: resolve_access_token,
      uri_base: uri_base,
      log_errors: Rails.env.development?
    )
    setup_model
  rescue StandardError => e
    raise "Failed to initialize OpenAI client: #{e.message}"
  end

  private

  # Config da key OpenAI deste serviço. Subclasses (ex.: transcrição de áudio)
  # sobrescrevem pra usar uma key por-propósito; cai em CAPTAIN_OPEN_AI_API_KEY
  # se a config específica estiver vazia.
  def api_key_config_name
    'CAPTAIN_OPEN_AI_API_KEY'
  end

  def resolve_access_token
    InstallationConfig.find_by(name: api_key_config_name)&.value.presence ||
      InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value
  end

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def uri_base
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    endpoint.presence || 'https://api.openai.com/'
  end

  def setup_model
    config_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
    @model = (config_value.presence || DEFAULT_MODEL)
  end
end
