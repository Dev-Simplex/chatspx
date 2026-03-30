# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :temperature, :account

  def initialize(account: nil)
    Llm::Config.initialize!
    @account = account
    setup_model
    setup_temperature
  end

  def chat(model: nil, temperature: @temperature)
    selected_model = model.presence || model_for_feature
    @model = selected_model
    context_for_account.chat(model: selected_model).with_temperature(temperature)
  end

  def refresh_model!
    @model = model_for_feature
  end

  private

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    @model = model_for_feature
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end

  def model_for_feature
    key = feature_name.presence || 'assistant'
    candidates = model_candidates_for_feature(key)
    selected_model = Llm::Models.first_runtime_supported(*candidates)
    fallback_model = selected_model.presence || DEFAULT_MODEL

    log_invalid_model_candidates(
      feature_key: key,
      candidates: candidates,
      fallback_model: fallback_model
    )

    fallback_model
  end

  def model_from_account_preferences(feature_key)
    method_name = "captain_#{feature_key}_model"
    return unless resolved_account.respond_to?(method_name)

    resolved_account.public_send(method_name)
  end

  def model_candidates_for_feature(feature_key)
    [
      model_from_account_preferences(feature_key),
      Llm::Models.default_model_for(feature_key),
      DEFAULT_MODEL
    ].compact_blank.uniq
  end

  def log_invalid_model_candidates(feature_key:, candidates:, fallback_model:)
    unsupported_models = candidates.reject { |candidate| Llm::Models.runtime_supported_model?(candidate) }
    return if unsupported_models.blank?

    unsupported_models.each do |invalid_model|
      Rails.logger.warn(
        "#{self.class.name} account_id=#{resolved_account&.id} " \
        "feature_name=#{feature_key} invalid_model=#{invalid_model} " \
        "fallback_model=#{fallback_model}"
      )
    end
  end

  def context_for_account
    Llm::Config.context_for_account(account: resolved_account)
  end

  def resolved_account
    @account || @assistant&.account || @conversation&.account
  end

  def feature_name
    nil
  end
end
