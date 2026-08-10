# Grava o trace de cada tool call da IA (Eval 2.0 F2). Prependado em TODA subclasse
# de BasePublicTool (hook inherited): intercepta perform, mede, trunca o resultado e
# persiste em captain_tool_calls. Best-effort por construção — NUNCA quebra a tool
# (falha de trace só loga) e NUNCA altera o resultado. Só grava quando a conta tem
# eval_enabled (config-first, multi-tenant).
module Captain::Tools::TraceRecorder
  RESULT_PREVIEW_LIMIT = 1500

  def perform(tool_context, **kwargs)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @tool_trace_exception = nil
    result = super
    record_tool_trace(tool_context, kwargs, result, started, @tool_trace_exception)
    result
  rescue StandardError => e
    record_tool_trace(tool_context, kwargs, nil, started, e)
    raise
  end

  private

  def record_tool_trace(tool_context, kwargs, result, started, exception)
    account = @assistant&.account
    return unless account && Captain::ConversationEval.enabled_for?(account)

    conversation = find_trace_conversation(tool_context&.state, account)
    return unless conversation

    Captain::ToolCall.create!(
      account_id: account.id,
      conversation_id: conversation.id,
      captain_assistant_id: @assistant.id,
      tool_name: trace_tool_name,
      args: Captain::Tools::SensitiveDataSanitizer.sanitize(kwargs),
      result_preview: exception ? nil : truncate_result(result),
      status: exception ? 'error' : 'ok',
      error: exception && Captain::Tools::SensitiveDataSanitizer.sanitize("#{exception.class}: #{exception.message}")[0, 200],
      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
      created_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("[tool-trace] falhou ao gravar trace de #{self.class.name}: #{e.class} #{e.message}")
  end

  def truncate_result(result)
    text = result.is_a?(String) ? result : result.inspect
    Captain::Tools::SensitiveDataSanitizer.sanitize(text.to_s)[0, RESULT_PREVIEW_LIMIT]
  end

  def find_trace_conversation(state, account)
    conversation_id = state&.dig(:conversation, :id)
    return unless conversation_id

    ::Conversation.find_by(id: conversation_id, account_id: account.id)
  end

  def trace_tool_name
    return @custom_tool.slug if defined?(@custom_tool) && @custom_tool&.slug.present?

    self.class.name.demodulize.underscore.delete_suffix('_tool')
  end
end
