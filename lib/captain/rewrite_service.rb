class Captain::RewriteService < Captain::BaseTaskService
  pattr_initialize [:account!, :content!, :operation!, { conversation_display_id: nil }]

  TONE_OPERATIONS = %i[casual professional friendly confident straightforward].freeze
  ALLOWED_OPERATIONS = (%i[fix_spelling_grammar improve shorten expand] + TONE_OPERATIONS).freeze

  def perform
    operation_sym = operation.to_sym
    raise ArgumentError, "Invalid operation: #{operation}" unless ALLOWED_OPERATIONS.include?(operation_sym)

    send(operation_sym)
  end

  TONE_OPERATIONS.each do |tone|
    define_method(tone) do
      call_llm_with_prompt(tone_rewrite_prompt(tone.to_s))
    end
  end

  private

  def fix_spelling_grammar
    call_llm_with_prompt(prompt_from_file('fix_spelling_grammar'))
  end

  def improve
    template = prompt_from_file('improve')

    sanitized_context = Captain::PiiSanitizer.sanitize(
      conversation.to_llm_text(include_contact_details: true)
    )
    sanitized_content = Captain::PiiSanitizer.sanitize(content)

    system_prompt = render_liquid_template(template, {
                                             'conversation_context' => sanitized_context,
                                             'draft_message' => sanitized_content
                                           })

    call_llm_with_prompt(system_prompt, sanitized_content)
  end

  def shorten
    template = prompt_from_file('shorten')
    sanitized = Captain::PiiSanitizer.sanitize(content)
    system_prompt = render_liquid_template(template, 'content' => sanitized)
    call_llm_with_prompt(system_prompt, sanitized)
  end

  def expand
    template = prompt_from_file('expand')
    sanitized = Captain::PiiSanitizer.sanitize(content)
    system_prompt = render_liquid_template(template, 'content' => sanitized)
    call_llm_with_prompt(system_prompt, sanitized)
  end

  # Defense-in-depth: sanitize the user payload here too, so callers that
  # forget to pre-sanitize (e.g. fix_spelling_grammar / tone operations
  # invoked with raw content) never leak PII to the upstream LLM provider.
  # Pre-sanitized inputs are idempotent under Captain::PiiSanitizer.
  def call_llm_with_prompt(system_content, user_content = nil)
    sanitized_user = Captain::PiiSanitizer.sanitize(user_content || content)
    make_api_call(
      feature: 'editor',
      messages: [
        { role: 'system', content: system_content },
        { role: 'user', content: sanitized_user }
      ]
    )
  end

  def render_liquid_template(template_content, variables = {})
    Liquid::Template.parse(template_content).render(variables)
  end

  def tone_rewrite_prompt(tone)
    template = prompt_from_file('tone_rewrite')
    render_liquid_template(template, 'tone' => tone)
  end

  def event_name
    operation
  end

  def use_account_openai_hook?
    true
  end
end
