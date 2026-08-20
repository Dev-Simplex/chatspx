class Captain::SummaryService < Captain::BaseTaskService
  pattr_initialize [:account!, :conversation_display_id!]

  def perform
    make_api_call(
      model: GPT_MODEL,
      messages: [
        { role: 'system', content: prompt_from_file('summary') },
        { role: 'user', content: sanitized_conversation_text }
      ]
    )
  end

  private

  def sanitized_conversation_text
    raw = conversation.to_llm_text(include_contact_details: false)
    Captain::PiiSanitizer.sanitize(raw)
  end

  def event_name
    'summarize'
  end
end
