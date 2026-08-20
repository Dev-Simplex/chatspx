# Tool de retrieval para o agente: busca passagens na base de conhecimento (chunks de
# documentos) por busca HÍBRIDA (semântica vetorial + termo exato full-text, fundidos por RRF).
# Complementa o faq_lookup (que busca só FAQ Q&A). Genérica e multi-tenant.
class Captain::Tools::SearchKnowledgeTool < Captain::Tools::BasePublicTool
  description 'Search the knowledge base documents for relevant passages using hybrid semantic + keyword retrieval'
  param :query, type: 'string', desc: 'The question or topic to look up in the knowledge base'

  def perform(_tool_context, query:)
    log_tool_usage('searching', { query: query })

    chunks = Captain::DocumentChunk.hybrid_search(
      query,
      assistant_id: @assistant.id,
      account_id: @assistant.account_id
    )

    if chunks.empty?
      log_tool_usage('no_results', { query: query })
      "No relevant knowledge found for: #{query}"
    else
      log_tool_usage('found_results', { query: query, count: chunks.size })
      chunks.each { |chunk| record_citation(chunk) }
      chunks.map { |chunk| format_chunk(chunk) }.join("\n---\n")
    end
  end

  private

  def format_chunk(chunk)
    source = chunk.metadata&.dig('name').presence || chunk.metadata&.dig('source')
    # Entrega o mesmo texto que foi embeddado: quando o contextual retrieval está
    # ligado na conta, `contextual_content` é "1-2 frases situando o trecho" + o
    # próprio trecho, então o agente recebe a passagem já situada no documento.
    # Conta sem o recurso (ou chunk antigo) cai no conteúdo puro, como antes.
    text = (chunk.contextual_content.presence || chunk.content).to_s.strip
    source.present? ? "#{text}\n(fonte: #{source})" : text
  end

  # 6.03: a mesma fonte que vai como prosa para o modelo vai como DADO para a mensagem.
  # A prosa continua (o modelo a usa para escrever); o metadado é o que o visitante vê,
  # o que sobrevive ao reload e o que pode virar link. Best-effort: falha aqui não pode
  # derrubar a busca — a resposta sem citação é pior, mas resposta nenhuma é muito pior.
  def record_citation(chunk)
    Captain::CitationWindow.record(
      title: chunk.metadata&.dig('name'),
      source: chunk.metadata&.dig('source'),
      excerpt: chunk.content
    )
  rescue StandardError => e
    Rails.logger.warn("[citation] falhou ao registrar fonte do chunk #{chunk&.id}: #{e.class} #{e.message}")
  end
end
