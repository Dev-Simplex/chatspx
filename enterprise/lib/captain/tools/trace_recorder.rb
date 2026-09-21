# Grava o trace de cada tool call da IA (Eval 2.0 F2). Prependado em TODA subclasse
# de BasePublicTool (hook inherited) e no Captain::Tools::HttpTool, que não herda dela —
# sem esse segundo prepend as custom tools de todos os tenants ficavam sem trace nenhum.
# Intercepta perform, mede, trunca o resultado e persiste em captain_tool_calls.
# Best-effort por construção — NUNCA quebra a tool (falha de trace só loga) e NUNCA altera o
# resultado que a gem recebe. Só grava quando a conta pede o trace — para julgar o atendimento
# depois (eval) ou para devolver o retorno ao contexto do turno seguinte (ToolContextNote).
# Ver Captain::ToolCall.gravar_para? (config-first, multi-tenant).
#
# É AQUI que o Captain::Tools::Result é desembrulhado: a ferramenta devolve o tipo, o banco
# recebe o status semântico e a gem continua recebendo String, como sempre recebeu.
module Captain::Tools::TraceRecorder
  RESULT_PREVIEW_LIMIT = 1500

  def perform(tool_context, **kwargs)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    bruto = super
    record_tool_trace(tool_context, kwargs, bruto, started, nil)
    # Tool ainda não tipada devolve o que sempre devolveu, intocado — inclusive quando não é
    # String. Só o Result atravessa convertido.
    Captain::Tools::Result.tipado?(bruto) ? bruto.to_s : bruto
  rescue StandardError => e
    record_tool_trace(tool_context, kwargs, nil, started, e)
    raise
  end

  private

  def record_tool_trace(tool_context, kwargs, resultado, started, exception)
    account = @assistant&.account
    return unless account && Captain::ToolCall.gravar_para?(account)

    conversation = trace_conversation(tool_context&.state)
    return unless conversation

    Captain::ToolCall.create!(
      account_id: account.id,
      conversation_id: conversation.id,
      captain_assistant_id: @assistant.id,
      tool_name: self.class.name.demodulize.underscore.delete_suffix('_tool'),
      args: sanitize_trace(kwargs),
      result_preview: preview(resultado, exception),
      status: status_semantico(resultado, exception),
      error: motivo_do_erro(resultado, exception),
      duration_ms: decorrido_ms(started),
      created_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("[tool-trace] falhou ao gravar trace de #{self.class.name}: #{e.class} #{e.message}")
  end

  # Exceção não deixa retorno: o que houve está no campo `error`, não no preview.
  def preview(resultado, exception)
    exception ? nil : truncate_result(resultado)
  end

  def decorrido_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end

  # Sucesso é SEMÂNTICO, não ausência de exceção. Antes, toda tool que capturava o próprio erro
  # e devolvia "Não consegui..." era gravada como 'ok' — e a nota do turno seguinte a mostrava
  # como fato consultado. Agora quem devolve Result carrega o próprio status; quem ainda devolve
  # String continua em 'ok' (nenhuma regressão, e a dívida está nomeada no PR).
  def status_semantico(resultado, exception)
    return 'error' if exception
    return resultado.status_persistido if Captain::Tools::Result.tipado?(resultado)

    'ok'
  end

  def motivo_do_erro(resultado, exception)
    return "#{exception.class}: #{exception.message}"[0, 200] if exception
    return nil unless Captain::Tools::Result.tipado?(resultado)

    resultado.detalhe.presence&.to_s&.slice(0, 200)
  end

  # Conversa do turno. Deliberadamente NÃO usa o `find_conversation` do BasePublicTool: o
  # HttpTool não herda dele e precisa do mesmo trace. Mesmo escopo por conta (multi-tenant).
  def trace_conversation(state)
    conversation_id = state&.dig(:conversation, :id)
    return nil if conversation_id.blank?

    ::Conversation.find_by(id: conversation_id, account_id: @assistant.account_id)
  end

  def truncate_result(resultado)
    text = if Captain::Tools::Result.tipado?(resultado)
             resultado.to_s
           else
             resultado.is_a?(String) ? resultado : resultado.inspect
           end
    sanitize_trace(text.to_s[0, RESULT_PREVIEW_LIMIT])
  end

  # remove null bytes / controle C0 (o Postgres recusa em text/jsonb)
  def sanitize_trace(obj)
    case obj
    when String then obj.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, '')
    when Array then obj.map { |v| sanitize_trace(v) }
    when Hash then obj.transform_values { |v| sanitize_trace(v) }
    else obj
    end
  end
end
