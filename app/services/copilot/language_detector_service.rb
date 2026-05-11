class Copilot::LanguageDetectorService
  CACHE_TTL = 1.hour
  DEFAULT_LANGUAGE = 'pt-BR'.freeze
  ALLOWED_LANGUAGES = %w[pt-BR en es fr de it ja zh].freeze
  MAX_SAMPLE_CHARS = 600

  def initialize(conversation:, account: nil)
    @conversation = conversation
    @account = account || conversation&.account
  end

  def perform
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { detect }
  end

  private

  attr_reader :conversation

  def cache_key
    "copilot:lang:c#{conversation.id}"
  end

  def detect
    return DEFAULT_LANGUAGE if api_key.blank?

    sample = build_sample
    return DEFAULT_LANGUAGE if sample.blank?

    response = call_openai(sample)
    Copilot::OpenaiSettings.log_chat_usage(
      service: 'language_detector', account: @account, model: model, response: response
    )
    code = response.dig('choices', 0, 'message', 'content').to_s.strip
    ALLOWED_LANGUAGES.include?(code) ? code : DEFAULT_LANGUAGE
  rescue StandardError => e
    Rails.logger.warn("[Copilot::LanguageDetectorService] #{e.class}: #{e.message}")
    DEFAULT_LANGUAGE
  end

  def build_sample
    conversation.messages
                .where(message_type: :incoming, private: false)
                .where.not(content: [nil, ''])
                .order(created_at: :desc)
                .limit(5)
                .pluck(:content)
                .join("\n")[0, MAX_SAMPLE_CHARS]
  end

  def call_openai(sample)
    OpenAI::Client.new(access_token: api_key).chat(
      parameters: {
        model: model,
        max_tokens: 8,
        temperature: 0,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: sample }
        ]
      }
    )
  end

  def api_key
    @api_key ||= Copilot::OpenaiSettings.api_key(@account)
  end

  def model
    @model ||= Copilot::OpenaiSettings.default_model(@account)
  end

  def system_prompt
    "Detect the language of the text. Respond with ONLY one of these BCP-47 codes: #{ALLOWED_LANGUAGES.join(', ')}. " \
      'Default to pt-BR for Portuguese. Respond with the code only, no explanations.'
  end
end
