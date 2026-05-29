# Quebra o conteúdo de um Document em chunks, opcionalmente contextualiza (Anthropic
# contextual retrieval) e dispara o embedding de cada chunk. Coexiste com o
# ResponseBuilderJob (FAQ) — qual roda depende do knowledge_mode da Assistant.
class Captain::Documents::ChunkBuilderJob < ApplicationJob
  queue_as :low

  def perform(document)
    return if document.content.blank?
    return unless document.assistant.chunk_knowledge_enabled?

    reset_previous_chunks(document)
    build_chunks(document)
  rescue Llm::Config::MissingAccountApiKeyError => e
    Rails.logger.warn("[ChunkBuilderJob] sem API key p/ doc #{document.id}: #{e.message}")
  end

  private

  def reset_previous_chunks(document)
    document.document_chunks.destroy_all
  end

  def build_chunks(document)
    pieces = Captain::Llm::DocumentChunkingService.new(document.content).chunks
    contextualizer = build_contextualizer(document)

    pieces.each_with_index do |piece, index|
      create_chunk(document, piece, index, contextualizer)
    end
  end

  def create_chunk(document, piece, index, contextualizer)
    document.document_chunks.create!(
      account: document.account,
      assistant: document.assistant,
      position: index,
      content: piece,
      contextual_content: contextualizer&.contextualize(piece),
      metadata: { 'source' => document.external_link, 'name' => document.name }
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[ChunkBuilderJob] chunk inválido doc #{document.id}: #{e.message}")
  end

  def build_contextualizer(document)
    return nil unless document.assistant.contextual_chunks_enabled?

    Captain::Llm::ContextualChunkService.new(document.content, account_id: document.account_id)
  end
end
