class Copilot::GhostSuggestionService
  MAX_INCOMING_CHARS = 600
  MAX_TOKENS = 80
  CACHE_TTL = 5.minutes

  def initialize(conversation:, language: 'pt-BR', account: nil)
    @conversation = conversation
    @language = language
    @account = account || conversation&.account
  end

  def perform
    return nil if api_key.blank?
    return nil if last_incoming.blank?

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { generate_suggestion }
  end

  private

  attr_reader :conversation, :language

  def api_key
    @api_key ||= Copilot::OpenaiSettings.api_key(@account)
  end

  def model
    @model ||= Copilot::OpenaiSettings.default_model(@account)
  end

  def last_incoming
    @last_incoming ||= conversation.messages
                                   .where(message_type: :incoming, private: false)
                                   .where.not(content: [nil, ''])
                                   .order(created_at: :desc)
                                   .first
  end

  def cache_key
    "copilot:ghost:c#{conversation.id}:m#{last_incoming.id}:l#{language}:mdl#{model}"
  end

  def generate_suggestion
    response = OpenAI::Client.new(access_token: api_key).chat(
      parameters: {
        model: model,
        max_tokens: MAX_TOKENS,
        temperature: 0.5,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_prompt }
        ]
      }
    )
    Copilot::OpenaiSettings.log_chat_usage(service: 'ghost_suggestion', account: @account, model: model, response: response)
    text = response.dig('choices', 0, 'message', 'content').to_s.strip
    text.delete_prefix('"').delete_suffix('"').presence
  rescue StandardError => e
    Rails.logger.warn("[GhostSuggestionService] #{e.class}: #{e.message}")
    nil
  end

  def system_prompt
    <<~PROMPT
      Você é um assistente que ajuda agentes de atendimento a responder rapidamente.
      Gere apenas UMA sugestão de resposta curta e profissional em #{language}.
      Limite: 140 caracteres. Sem aspas. Sem prefixo. Apenas a frase a ser enviada.
      Tom: humano, atencioso, direto. Não use emoji.
    PROMPT
  end

  def user_prompt
    content = last_incoming.content.to_s.strip[0, MAX_INCOMING_CHARS]
    "Mensagem do cliente: #{content}\nSugestão de resposta:"
  end
end
