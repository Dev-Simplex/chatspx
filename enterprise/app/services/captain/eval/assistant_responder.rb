# O respondedor PADRÃO de um caso de eval (bloco 6.02).
#
# Usa `AgentRunnerService#run_raw` com `conversation: nil` — o caminho que já existia no
# repositório para "rodar o engine e devolver o resultado cru, sem alterar o caminho de
# produção". Consequência que é o ponto do bloco:
#
#   NENHUMA conversa é criada, NENHUMA mensagem é gravada, NADA é entregue a visitante.
#
# É por isso que a execução só existe em `dry_run`: não há um modo "contra a IA de
# produção" para o cliente ligar por engano — ele não foi construído (ver RunService).
#
# As ferramentas chamadas saem da janela do 6.01 (Captain::ToolTraceWindow), a mesma que
# o guardrail lê em produção — e não de uma leitura própria do resultado do runner.
class Captain::Eval::AssistantResponder
  def call(assistant:, mensagens:)
    Captain::ToolTraceWindow.open!
    resultado = runner(assistant).run_raw(message_history: turnos(mensagens))
    chamadas = Captain::ToolTraceWindow.calls
    {
      resposta: texto_de(resultado),
      ferramentas: chamadas.pluck(:tool_name).uniq,
      tool_calls: chamadas,
      handoff: handoff_em?(chamadas)
    }
  ensure
    Captain::ToolTraceWindow.close!
  end

  private

  def runner(assistant)
    Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: nil)
  end

  def turnos(mensagens)
    mensagens.map { |texto| { content: texto, role: 'user' } }
  end

  # O que o juiz julga é a FALA — não o inspect do Hash de saída.
  #
  # Todo assistente roda com `Captain::ResponseSchema`, então `resultado.output` é
  # `{"response" => ..., "reasoning" => ...}`. Ler `output.to_s` aqui punha o raciocínio
  # do modelo dentro do texto julgado: um caso com `nao_contem: ["desconto"]` reprovava
  # porque o RACIOCÍNIO dizia "evitei falar de desconto", e a resposta não dizia nada
  # disso. E o turno que termina em transferência, cujo `response` vem vazio, era
  # julgado como string vazia em vez do "vou te passar pra Bruna" que o cliente leria.
  #
  # `Captain::AgentOutput` é a mesma leitura que o caminho de produção
  # (AgentRunnerService) faz — inclusive o fallback de handoff.
  def texto_de(resultado)
    Captain::AgentOutput.text_from(resultado)
  end

  def handoff_em?(chamadas)
    chamadas.any? { |c| c[:tool_name].to_s.match?(/handoff|transferir/) }
  end
end
