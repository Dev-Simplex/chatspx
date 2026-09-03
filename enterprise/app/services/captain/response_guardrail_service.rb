# Guardrail de PRÉ-ENVIO (bloco 6.01).
#
# Os mesmos asserts que o eval roda depois do episódio [M18] passam a rodar ANTES de a
# resposta sair. Recebe a resposta candidata + as tool calls da janela desta resposta e
# devolve `passa` ou `retém`.
#
# CUSTO ZERO DE LLM: nada aqui chama modelo. São regex e comparação de string
# (Captain::GateAsserts), no padrão τ-bench/BFCL.
#
# ─── A ASSIMETRIA DE DANO, e por que a retenção termina em handoff ──────────────────
# Reter uma resposta tem dois modos de falha, e eles não custam o mesmo:
#
#   barato → o visitante vê a SAÍDA HUMANA. Perde-se uma resposta que talvez estivesse
#            certa, e alguém do time assume. Custo: um atendimento a mais na fila.
#   caro   → o visitante fica numa conversa que não anda: ou recebe uma afirmação falsa
#            com a marca do cliente na tela, ou não recebe nada e some.
#
# Por isso reter NUNCA significa silêncio: significa `bot_handoff!` com a mensagem de
# transferência (e o OOO quando fora do horário) — o caminho que o produto já tem para
# entregar o visitante a uma pessoa. E por isso um ERRO DENTRO DO GUARDRAIL libera a
# resposta em vez de segurá-la: um bug meu não pode calar o atendimento de ninguém.
# É a mesma regra do `rescue` de episode_eval_job.rb — em erro, libera e registra.
class Captain::ResponseGuardrailService
  # Quem RETÉM e quem só REGISTRA. Retêm as duas famílias em que o fato é binário e o
  # dano é direto no visitante:
  #   contradisse_tool → a ferramenta trouxe resultado e a resposta nega tê-lo;
  #   repeticao        → texto idêntico ao que a IA já mandou: a conversa não anda.
  # `ignorou_erro_da_tool` NÃO retém: a ferramenta ter falhado não torna a resposta
  # falsa (a IA pode ter respondido de outra fonte, ou nem depender daquele dado).
  # Reter aí trocaria ruído por handoff em massa — dano caro, do outro lado.
  RETAINING_CATEGORIES = %w[contradisse_tool repeticao].freeze

  # Repetição literal só conta como bot-loop dentro de uma janela curta. A mesma
  # resposta correta uma semana depois, para a mesma pergunta repetida, é legítima.
  REPETITION_LOOKBACK = 30.minutes
  REPETITION_DEPTH = 10

  Result = Struct.new(:findings, keyword_init: true) do
    def retains?
      findings.any? { |f| Captain::ResponseGuardrailService::RETAINING_CATEGORIES.include?(f['categoria']) }
    end

    def passes?
      !retains?
    end

    # Uma linha, para o log de comportamento e para a nota que o time lê.
    def reason
      findings.select { |f| Captain::ResponseGuardrailService::RETAINING_CATEGORIES.include?(f['categoria']) }
              .map { |f| f['porque'] }.join(' · ')
    end
  end

  def initialize(conversation:, candidate:, tool_calls: [])
    @conversation = conversation
    @candidate = candidate.to_s
    @tool_calls = Array(tool_calls)
  end

  def perform
    return Result.new(findings: []) if @candidate.blank?

    Result.new(findings: contradiction_findings + tool_error_findings + repetition_findings)
  end

  private

  def contradiction_findings
    @tool_calls.filter_map do |call|
      next unless Captain::GateAsserts.contradicts_tool?(
        @candidate, status: call[:status], result_preview: call[:result_preview]
      )

      Captain::GateAsserts.finding(
        categoria: 'contradisse_tool',
        trecho: @candidate,
        porque: "a ferramenta #{call[:tool_name]} devolveu resultados e a resposta ia negar tê-los encontrado"
      )
    end
  end

  def tool_error_findings
    @tool_calls.select { |call| call[:status].to_s == 'error' }.map do |call|
      Captain::GateAsserts.finding(
        categoria: 'ignorou_erro_da_tool',
        severidade: 'media',
        trecho: @candidate,
        porque: "a ferramenta #{call[:tool_name]} falhou (#{call[:error].to_s[0, 80]}) antes desta resposta"
      )
    end
  end

  def repetition_findings
    key = Captain::GateAsserts.repetition_key(@candidate)
    return [] if key.nil?
    return [] unless recent_ia_keys.include?(key)

    [Captain::GateAsserts.finding(
      categoria: 'repeticao',
      trecho: @candidate,
      porque: 'a resposta é literalmente igual a uma que a IA já enviou nesta conversa'
    )]
  end

  # As últimas respostas que a IA de fato enviou nesta conversa, normalizadas.
  def recent_ia_keys
    @recent_ia_keys ||= @conversation.messages
                                     .where(message_type: :outgoing, private: false, sender_type: 'Captain::Assistant')
                                     .where(created_at: REPETITION_LOOKBACK.ago..)
                                     .reorder(created_at: :desc)
                                     .limit(REPETITION_DEPTH)
                                     .pluck(:content)
                                     .filter_map { |content| Captain::GateAsserts.repetition_key(content) }
                                     .to_set
  end
end
