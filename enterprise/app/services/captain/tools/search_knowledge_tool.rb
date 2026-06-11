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
      chunks.map { |chunk| format_chunk(chunk) }.join("\n---\n")
    end
  end

  private

  def format_chunk(chunk)
    source = chunk.metadata&.dig('name').presence || chunk.metadata&.dig('source')
    text = chunk.content.to_s.strip
    source.present? ? "#{text}\n(fonte: #{source})" : text
  end
end
