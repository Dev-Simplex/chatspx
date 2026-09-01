# Como se lê o TEXTO que a IA falou, a partir do `RunResult` cru do engine.
#
# Todo assistente do Captain roda com `Captain::ResponseSchema` (ver
# Concerns::Agentable#agent_response_schema), então `result.output` NÃO é a fala: é
#
#   {"response" => "Abrimos das 9h", "reasoning" => "o usuário pediu desconto, evitei"}
#
# Quem faz `output.to_s` lê o inspect do Hash INTEIRO — com o raciocínio do modelo
# dentro. O raciocínio fala de coisas que a resposta não fala, e é por isso que a
# diferença não é cosmética: um juiz de texto (o eval do 6.02) passa a reprovar por
# palavra que só existe no pensamento, e a fala do turno de transferência — que o
# schema devolve vazia — vira string vazia em vez do "vou te passar pra Bruna".
#
# Este módulo é o único lugar onde essa leitura mora. Antes ela existia duas vezes
# (AgentRunnerService, privada) e uma terceira, ERRADA, no respondedor do eval.
module Captain::AgentOutput
  # Estrutura de saída serializada no formato cru do inspect, com hash-rocket.
  SERIALIZED_OUTPUT = /\A\{.*["']response["']\s*=>/m
  SERIALIZED_RESPONSE_FIELD = /["']response["']\s*=>\s*"((?:[^"\\]|\\.)*)"/m

  module_function

  # O texto para o cliente, a partir do `RunResult` cru — com o fallback de handoff.
  def text_from(result)
    return result.to_s unless result.respond_to?(:output)

    from_output(result.output).presence || last_assistant_text(result)
  end

  # `output` é Hash sempre que o agente roda com `response_schema`.
  def from_output(output)
    return output.to_s unless output.is_a?(Hash)

    (output['response'] || output[:response]).to_s
  end

  # Quando o último turno é um handoff (ou o agente não produz output final),
  # `result.output` volta vazio — mas o texto para o cliente ficou na última mensagem
  # do assistente, antes da tool call de transferência.
  def last_assistant_text(result)
    messages = result.try(:messages)
    return '' if messages.blank?

    conteudo = content_of_last_assistant(messages)
    return '' if conteudo.blank?

    unwrap(conteudo)
  end

  # O modelo às vezes serializa a PRÓPRIA estrutura de saída em vez de devolver só o
  # texto. Em JSON válido o parse resolve; em hash-rocket, não — e a estrutura inteira
  # viraria a fala do agente.
  def unwrap(content)
    return from_output(content) if content.is_a?(Hash)

    parsed = parse_json(content)
    return parsed['response'].to_s if parsed.is_a?(Hash) && parsed['response'].present?
    return content.to_s unless content.to_s.strip.match?(SERIALIZED_OUTPUT)

    content.to_s.match(SERIALIZED_RESPONSE_FIELD)&.captures&.first.to_s
  end

  def content_of_last_assistant(messages)
    ultima = messages.reverse.find do |msg|
      papel = msg[:role] || msg['role']
      conteudo = msg[:content] || msg['content']
      papel.to_s == 'assistant' && conteudo.present?
    end
    ultima && (ultima[:content] || ultima['content'])
  end

  def parse_json(content)
    JSON.parse(content)
  rescue StandardError
    nil
  end
end
