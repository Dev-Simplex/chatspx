class Llm::AccountScopedContext
  thread_mattr_accessor :ruby_llm_context
  thread_mattr_accessor :current_account_id

  module ChatThreadContextPatch
    def initialize(*args, context: nil, **kwargs)
      context ||= Llm::AccountScopedContext.current_context
      super(*args, context: context, **kwargs)
    end
  end

  class << self
    def with_account(account)
      previous_context = ruby_llm_context
      previous_account_id = current_account_id

      self.ruby_llm_context = Llm::Config.context_for_account(account: account)
      self.current_account_id = account&.id

      yield ruby_llm_context
    ensure
      self.ruby_llm_context = previous_context
      self.current_account_id = previous_account_id
    end

    def current_context
      ruby_llm_context
    end

    def install_ruby_llm_patch!
      return unless defined?(RubyLLM::Chat)
      return if RubyLLM::Chat.ancestors.include?(ChatThreadContextPatch)

      RubyLLM::Chat.prepend(ChatThreadContextPatch)
    end
  end
end
