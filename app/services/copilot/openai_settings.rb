class Copilot::OpenaiSettings
  DEFAULT_MODEL = 'gpt-4o-mini'.freeze
  ADVANCED_MODEL = 'gpt-4o'.freeze
  VISION_MODEL = 'gpt-4o-mini'.freeze

  CHAT_MODELS_PRICING = {
    'gpt-4o-mini' => { input: 0.15, output: 0.60 },
    'gpt-4o' => { input: 2.50, output: 10.00 },
    'gpt-4-turbo' => { input: 10.00, output: 30.00 },
    'o1-mini' => { input: 3.00, output: 12.00 },
    'o1-preview' => { input: 15.00, output: 60.00 }
  }.freeze

  WHISPER_COST_PER_MINUTE = 0.006

  class << self
    def api_key(account)
      account_key = account&.settings&.dig('openai_api_key').to_s.strip
      env_key = ENV.fetch('OPENAI_API_KEY', nil).to_s.strip
      account_key.presence || env_key.presence
    end

    def default_model(account)
      account&.settings&.dig('openai_model_default').to_s.strip.presence || DEFAULT_MODEL
    end

    def advanced_model(account)
      account&.settings&.dig('openai_model_advanced').to_s.strip.presence || ADVANCED_MODEL
    end

    # Modelo de visao (descricao de midia) tem chave PROPRIA por conta, separada do
    # `openai_model_default`: o default de chat pode ser trocado por um modelo sem visao
    # e a descricao quebraria junto, sem ninguem relacionar uma coisa com a outra.
    def vision_model(account)
      account&.settings&.dig('openai_model_vision').to_s.strip.presence || VISION_MODEL
    end

    def log_chat_usage(service:, account:, model:, response:)
      usage = response.is_a?(Hash) ? response['usage'] : nil
      return if usage.blank?

      tokens_in = usage['prompt_tokens'].to_i
      tokens_out = usage['completion_tokens'].to_i
      cost = chat_cost(model, tokens_in, tokens_out)
      Rails.logger.info(
        "[OpenAI::Telemetry] service=#{service} account_id=#{account&.id || 'global'} model=#{model} " \
        "tokens_in=#{tokens_in} tokens_out=#{tokens_out} cost_usd=#{format('%.6f', cost)}"
      )
    end

    def log_audio_usage(service:, account:, duration_seconds:)
      cost = (duration_seconds.to_f / 60.0) * WHISPER_COST_PER_MINUTE
      Rails.logger.info(
        "[OpenAI::Telemetry] service=#{service} account_id=#{account&.id || 'global'} model=whisper-1 " \
        "duration_s=#{duration_seconds.to_i} cost_usd=#{format('%.6f', cost)}"
      )
    end

    def chat_cost(model, tokens_in, tokens_out)
      pricing = CHAT_MODELS_PRICING[model] || CHAT_MODELS_PRICING[DEFAULT_MODEL]
      ((tokens_in * pricing[:input]) + (tokens_out * pricing[:output])) / 1_000_000.0
    end
  end
end
