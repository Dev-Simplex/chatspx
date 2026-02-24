# frozen_string_literal: true

# DEPRECATED: This class uses the legacy OpenAI Ruby gem directly.
# Only used for PDF/file operations that require OpenAI's files API:
# - Captain::Llm::PdfProcessingService (files.upload for assistants)
# - Captain::Llm::PaginatedFaqGeneratorService (uses file_id from uploaded files)
#
# For all other LLM operations, use Llm::BaseAiService with RubyLLM instead.
class Llm::LegacyBaseOpenAiService
  DEFAULT_MODEL = 'gpt-4.1-mini'

  attr_reader :client, :model, :account

  def initialize(account:)
    @account = account
    resolver = Llm::AccountCredentialsResolver.new(account: account)
    api_key = resolver.openai_api_key
    raise Llm::Config::MissingAccountApiKeyError, I18n.t('captain.errors.missing_api_key') if api_key.blank?

    @client = OpenAI::Client.new(
      access_token: api_key,
      uri_base: resolver.openai_api_base,
      log_errors: Rails.env.development?
    )
    setup_model
  rescue Llm::Config::MissingAccountApiKeyError
    raise
  rescue StandardError => e
    raise "Failed to initialize OpenAI client: #{e.message}"
  end

  private

  def setup_model
    method_name = "captain_#{feature_name}_model"
    configured_model = account.respond_to?(method_name) ? account.public_send(method_name) : nil
    @model = configured_model.presence || DEFAULT_MODEL
  end

  def feature_name
    'assistant'
  end
end
