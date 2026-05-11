class Captain::SentimentAnalysisService < Captain::BaseTaskService
  pattr_initialize [:account!, :conversation_display_id!]

  # How many of the most recent (non-private) messages we feed to the LLM.
  # Sentiment is best read from the latest exchange, not the entire history.
  SENTIMENT_MESSAGE_WINDOW = 12

  def perform
    make_api_call(
      model: GPT_MODEL,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: 'Analise o tom emocional do cliente.' }
      ]
    )
  end

  private

  def system_prompt
    template = prompt_from_file('sentiment_analysis')
    Liquid::Template.parse(template).render('messages' => sanitized_messages_text)
  end

  def sanitized_messages_text
    sanitized_recent_messages.map do |message|
      role = message.incoming? ? 'Cliente' : 'Agente'
      "#{role}: #{Captain::PiiSanitizer.sanitize(message.content_for_llm)}"
    end.join("\n\n")
  end

  def sanitized_recent_messages
    return [] unless conversation

    conversation.messages
                .where(message_type: [:incoming, :outgoing])
                .where(private: false)
                .reorder('id desc')
                .limit(SENTIMENT_MESSAGE_WINDOW)
                .reverse
  end

  def event_name
    'sentiment_analysis'
  end
end
