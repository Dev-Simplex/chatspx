# Roda UM caso e devolve o veredito (bloco 6.02).
#
# O respondedor é injetável de propósito: em teste ele é um dublê, e nenhum exemplo
# desta base chama IA de verdade.
class Captain::Eval::CaseRunnerService
  def initialize(assistant:, eval_case:, responder: nil)
    @assistant = assistant
    @eval_case = eval_case
    @responder = responder || Captain::Eval::AssistantResponder.new
  end

  def perform
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    saida = @responder.call(assistant: @assistant, mensagens: @eval_case.turnos)
    veredito(saida, inicio)
  rescue StandardError => e
    # Um caso que estoura NÃO derruba o conjunto: ele reprova, dizendo por quê.
    {
      passou: false, resposta: nil, ferramentas: [], duracao_ms: 0,
      findings: [Captain::Eval::Expectations.finding('erro_de_execucao', "#{e.class}: #{e.message}"[0, 200])]
    }
  end

  private

  def veredito(saida, inicio)
    resposta = saida[:resposta].to_s
    ferramentas = Array(saida[:ferramentas]).map(&:to_s)
    findings = Captain::Eval::Expectations.evaluate(
      @eval_case.expectativas, resposta: resposta, ferramentas: ferramentas, handoff: saida[:handoff]
    ) + findings_do_guardrail(resposta, saida)

    {
      passou: findings.empty?,
      resposta: resposta,
      ferramentas: ferramentas,
      findings: findings,
      duracao_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
    }
  end

  # As MESMAS regras do guardrail de pré-envio (6.01): se esta resposta seria RETIDA em
  # produção, o caso reprova aqui — antes de o cliente publicar a mudança de prompt.
  # Só a família que depende de tool call entra: repetição precisa de conversa, e caso
  # de eval não tem conversa.
  def findings_do_guardrail(resposta, saida)
    Array(saida[:tool_calls]).filter_map do |call|
      next unless Captain::GateAsserts.contradicts_tool?(
        resposta, status: call[:status], result_preview: call[:result_preview]
      )

      Captain::GateAsserts.finding(
        categoria: 'contradisse_tool', trecho: resposta,
        porque: "a ferramenta #{call[:tool_name]} devolveu resultados e a resposta negou tê-los encontrado"
      )
    end
  end
end
