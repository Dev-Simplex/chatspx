require 'ruby_llm'

module Llm::Config
  class MissingAccountApiKeyError < StandardError; end

  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    def with_api_key(api_key, api_base: nil)
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = api_base
      end

      yield context
    end

    def context_for_account(account: nil, account_id: nil)
      resolved = account || (account_id && Account.find_by(id: account_id))
      resolver = Llm::AccountCredentialsResolver.new(account: resolved)

      RubyLLM.context do |config|
        openai_key = resolver.openai_api_key
        if openai_key.present?
          config.openai_api_key = openai_key
          config.openai_api_base = resolver.openai_api_base
        end

        anthropic_key = resolver.anthropic_api_key
        config.anthropic_api_key = anthropic_key if anthropic_key.present?
      end
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        config.openai_api_key = system_api_key if system_api_key.present?
        config.openai_api_base = openai_endpoint.chomp('/') if openai_endpoint.present?
        config.anthropic_api_key = system_anthropic_key if system_anthropic_key.present?
        config.logger = Rails.logger
      end
    end

    def system_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    end

    def system_anthropic_key
      InstallationConfig.find_by(name: 'CAPTAIN_ANTHROPIC_API_KEY')&.value
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    end
  end
end
