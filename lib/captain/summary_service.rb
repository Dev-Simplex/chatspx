class Captain::SummaryService < Captain::BaseTaskService
  pattr_initialize [:account!, :conversation_display_id!]

  def perform
    make_api_call(
      feature: 'editor',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: sanitized_conversation_text }
      ]
    )
  end

  private

  def sanitized_conversation_text
    raw = conversation.to_llm_text(include_contact_details: false)
    Captain::PiiSanitizer.sanitize(raw)
  end

  def system_prompt
    <<~PROMPT
      #{prompt_from_file('summary')}

      Reply in #{account.locale_english_name}.
    PROMPT
  end

  def event_name
    'summarize'
  end

  def use_account_openai_hook?
    true
  end
end
