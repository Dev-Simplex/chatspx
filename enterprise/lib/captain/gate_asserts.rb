# Os asserts determinísticos da IA, em UM lugar só (bloco 6.01).
#
# Antes deste arquivo as três famílias moravam dentro de `Captain::EpisodeGateService`,
# que roda DEPOIS do episódio, para alimentar o eval [M18]. O guardrail de pré-envio
# precisa das mesmas regras ANTES de a resposta sair — e duas cópias da mesma regra
# divergem no primeiro ajuste. Aqui elas são funções puras sobre dado cru (texto,
# status, preview), sem ActiveRecord e sem I/O: quem tem os fatos é quem chama.
#
# CUSTO ZERO DE LLM, por construção: tudo aqui é regex e comparação de string. É o
# padrão τ-bench/BFCL que o gate original já declarava — fato binário verificado por
# código, nunca por modelo.
module Captain::GateAsserts
  # "não encontrei", "não achei", "não temos", "não localizei"...
  NEGATIVE_REPLY = /n[ãa]o\s+(encontr|ach|localiz|temos|tem\b)/i
  # O retorno da ferramenta que já É um "nada encontrado" — negar depois dele não é contradição.
  EMPTY_RESULT = /nenhum|n[ãa]o encontr|not found|\A\s*\[\]\s*\z/i
  # Janela entre a tool call e a resposta que a contradiz.
  REPLY_WINDOW = 3.minutes
  # Abaixo disso, repetição literal é coincidência ("Claro!", "Perfeito, e o seu nome?"),
  # não bot-loop.
  MIN_REPEAT_LENGTH = 40

  module_function

  # A ferramenta devolveu algo utilizável? (erro não conta; retorno vazio não conta;
  # retorno que diz "nenhum resultado" não conta — o modelo estaria só repetindo o vazio)
  def tool_result_useful?(status:, result_preview:)
    return false if status.to_s == 'error'
    return false if result_preview.blank?

    !result_preview.to_s.match?(EMPTY_RESULT)
  end

  def negative_reply?(text)
    text.to_s.match?(NEGATIVE_REPLY)
  end

  # O flagra do "não achei imóvel" falso: a ferramenta trouxe resultado e a resposta nega.
  def contradicts_tool?(text, status:, result_preview:)
    tool_result_useful?(status: status, result_preview: result_preview) && negative_reply?(text)
  end

  # Chave de comparação literal. `nil` quando o texto é curto demais para o assert valer.
  def repetition_key(text)
    key = text.to_s.strip.downcase.gsub(/\s+/, ' ')
    return nil if key.length < MIN_REPEAT_LENGTH

    key
  end

  # O formato do finding é contrato com `captain_conversation_evals.response_findings`
  # (jsonb) e com quem o lê no painel. Muda aqui, muda nos dois consumidores.
  def finding(categoria:, porque:, severidade: 'alta', message_id: nil, trecho: nil)
    {
      'origem' => 'gate',
      'quem' => 'ia',
      'categoria' => categoria,
      'severidade' => severidade,
      'message_id' => message_id,
      'trecho' => trecho.to_s[0, 120],
      'porque' => porque
    }
  end
end
