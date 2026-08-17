class Captain::Llm::EmbeddingService
  include Integrations::LlmInstrumentation

  class EmbeddingsError < StandardError; end

  def initialize(account_id: nil, account: nil)
    Llm::Config.initialize!
    @account = account || Account.find_by(id: account_id)
    @account_id = @account&.id || account_id
    @embedding_model = @account&.captain_help_center_search_model.presence || self.class.embedding_model
  end

  def self.embedding_model
    LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def get_embedding(content, model: @embedding_model)
    return [] if content.blank?

    instrument_embedding_call(instrumentation_params(content, model)) do
      llm_context.embed(content, model: model).vectors
    end
  rescue RubyLLM::Error, Llm::Config::MissingAccountApiKeyError => e
    Rails.logger.error "Embedding API Error: #{e.message}"
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  private

  def llm_context
    Llm::Config.context_for_account(account: @account, account_id: @account_id)
  end

  def instrumentation_params(content, model)
    {
      span_name: 'llm.captain.embedding',
      model: model,
      input: content,
      feature_name: 'embedding',
      account_id: @account_id
    }
  end
end
