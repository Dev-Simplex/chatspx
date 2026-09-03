# Janela em memória das tool calls de UMA resposta (bloco 6.01).
#
# Por que não ler `captain_tool_calls`: aquela tabela só é escrita quando a conta tem
# `eval_enabled` (TraceRecorder#record_tool_trace), e o guardrail de pré-envio tem de
# valer para TODA conta — inclusive a que nunca ligou eval. Ler o banco também traria
# chamadas de respostas anteriores; aqui a janela é exatamente esta resposta.
#
# Contrato: quem gera a resposta ABRE antes e FECHA num `ensure`. Fora de uma janela
# aberta, `record` é no-op — nenhum caminho passa a acumular por acidente, e nada
# sobrevive à thread (Puma reusa threads; ver lib/current.rb).
module Captain::ToolTraceWindow
  # Teto de memória: uma resposta com mais de 50 tool calls é patológica, e o guardrail
  # não fica melhor com a 51ª.
  MAX_CALLS = 50

  module_function

  def open!
    Current.captain_tool_traces = []
  end

  def close!
    Current.captain_tool_traces = nil
  end

  def open?
    Current.captain_tool_traces.is_a?(Array)
  end

  def calls
    Array(Current.captain_tool_traces)
  end

  # `call` é um Hash simples — o guardrail não conhece ActiveRecord.
  def record(tool_name:, status:, result_preview:, error: nil)
    return unless open?
    return if Current.captain_tool_traces.size >= MAX_CALLS

    Current.captain_tool_traces << {
      tool_name: tool_name.to_s,
      status: status.to_s,
      result_preview: result_preview,
      error: error
    }
  end

  # Roda um bloco com a janela aberta e a fecha aconteça o que acontecer.
  def around
    open!
    yield
  ensure
    close!
  end
end
