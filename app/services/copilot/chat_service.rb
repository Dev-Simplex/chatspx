class Copilot::ChatService
  MAX_HISTORY = 8
  MAX_TOKENS = 320

  def initialize(conversation:, user_messages:, language: 'pt-BR', account: nil)
    @conversation = conversation
    @user_messages = user_messages || []
    @language = language
    @account = account || conversation&.account
  end

  def perform
    return nil if api_key.blank?

    response = OpenAI::Client.new(access_token: api_key).chat(
      parameters: {
        model: model,
        max_tokens: MAX_TOKENS,
        temperature: 0.4,
        messages: build_messages
      }
    )
    Copilot::OpenaiSettings.log_chat_usage(service: 'copilot_chat', account: @account, model: model, response: response)
    response.dig('choices', 0, 'message', 'content').to_s.strip.presence
  rescue StandardError => e
    Rails.logger.warn("[Copilot::ChatService] #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :conversation, :user_messages, :language

  def api_key
    @api_key ||= Copilot::OpenaiSettings.api_key(@account)
  end

  def model
    @model ||= Copilot::OpenaiSettings.default_model(@account)
  end

  def build_messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: conversation_context },
      *user_messages.last(MAX_HISTORY).map { |m| { role: m['role'], content: m['content'].to_s } }
    ]
  end

  def system_prompt
    <<~PROMPT
      Você é o Copilot do agente de atendimento. Responda em #{language}, direto e curto.
      Você tem acesso à conversa atual abaixo. Ajude o agente a:
      - resumir a conversa
      - sugerir próximos passos
      - escrever respostas para o cliente
      - identificar problemas urgentes
      Não invente dados. Cite trechos da conversa quando útil.
    PROMPT
  end

  def conversation_context
    contact = conversation.contact
    transcript = conversation.messages.where(private: false).order(created_at: :asc).last(20).map do |m|
      author = m.incoming? ? 'Cliente' : 'Agente'
      "#{author}: #{m.content.to_s.strip[0, 400]}"
    end.join("\n")
    <<~CTX
      Contato: #{contact&.name} #{contact&.email}
      Status: #{conversation.status}
      Prioridade: #{conversation.priority || 'sem prioridade'}

      Transcrição (últimas mensagens):
      #{transcript}
    CTX
  end
end
