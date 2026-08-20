# O custo de uma execução, ANTES de rodar (bloco 6.02).
#
# Custo aqui é na unidade em que o produto cobra: RESPOSTA. `increment_response_usage`
# soma 1 por resposta da IA, e um caso consome exatamente uma. O número de tokens é
# ESTIMATIVA declarada (heurística de caracteres), e está separado do número de créditos
# justamente para não parecer fatura: crédito é contagem exata, token é aproximação.
class Captain::Eval::CostEstimatorService
  # Heurística pública e conhecida (~4 caracteres por token em português/inglês). Não é
  # o tokenizer do modelo, e o nome do campo diz isso.
  CHARS_PER_TOKEN = 4
  # Sobra para a resposta que o modelo vai gerar, por caso.
  SAIDA_ESTIMADA_TOKENS = 250

  def initialize(assistant:, cases: nil)
    @assistant = assistant
    @cases = cases || assistant.eval_cases.ativos.ordenados
  end

  def perform
    quantidade = @cases.size
    {
      casos: quantidade,
      respostas: quantidade,
      tokens_estimados: tokens_estimados(quantidade),
      modelo: modelo,
      saldo: saldo,
      excede_saldo: saldo[:disponivel].present? && quantidade > saldo[:disponivel],
      base_da_estimativa: "#{CHARS_PER_TOKEN} caracteres por token + #{SAIDA_ESTIMADA_TOKENS} tokens de saída por caso"
    }
  end

  private

  def tokens_estimados(quantidade)
    entrada = @cases.sum { |c| c.turnos.join(' ').length }
    prompt = Captain::Eval::PromptIdentityService.new(assistant: @assistant).snapshot.to_json.length
    ((entrada + (prompt * quantidade)) / CHARS_PER_TOKEN) + (SAIDA_ESTIMADA_TOKENS * quantidade)
  end

  def modelo
    @assistant.config['model'].presence || Llm::Models.default_model_for('assistant')
  end

  def saldo
    limites = @assistant.account.usage_limits.dig(:captain, :responses) || {}
    {
      consumido: limites[:consumed],
      total: limites[:total_count],
      disponivel: limites[:current_available]
    }
  end
end
