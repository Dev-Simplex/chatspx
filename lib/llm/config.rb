require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4o-mini'.freeze
  class MissingAccountApiKeyError < StandardError; end

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      Llm::AccountScopedContext.install_ruby_llm_patch!
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
      account ||= Account.find_by(id: account_id) if account_id.present?
      raise MissingAccountApiKeyError, missing_api_key_message if account.blank?

      resolver = Llm::AccountCredentialsResolver.new(account: account)
      api_key = resolver.openai_api_key
      raise MissingAccountApiKeyError, missing_api_key_message if api_key.blank?

      RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = resolver.openai_api_base.chomp('/')
      end
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        config.openai_api_base = openai_endpoint.chomp('/') if openai_endpoint.present?
        config.logger = Rails.logger
      end
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    end

    def missing_api_key_message
      I18n.t('captain.errors.missing_api_key')
    end
  end
end
