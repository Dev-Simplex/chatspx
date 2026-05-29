# == Schema Information
#
# Table name: captain_document_chunks
#
#  id                  :bigint           not null, primary key
#  content             :text             not null
#  contextual_content  :text
#  content_search      :tsvector
#  embedding           :vector(1536)
#  metadata            :jsonb
#  position            :integer          default(0), not null
#  account_id          :bigint           not null
#  assistant_id        :bigint           not null
#  captain_document_id :bigint           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  idx_cap_doc_chunks_embedding_hnsw  (embedding) USING hnsw
#  idx_cap_doc_chunks_fulltext        (content_search) USING gin
#  idx_cap_doc_chunks_on_document     (captain_document_id)
#
# Unidade de RAG baseada em chunk (passagem), complementar à FAQ (Captain::AssistantResponse).
# Genérica e multi-tenant: escopada por account_id + assistant_id, sem nada específico de cliente.
class Captain::DocumentChunk < ApplicationRecord
  self.table_name = 'captain_document_chunks'

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :document, class_name: 'Captain::Document', foreign_key: :captain_document_id

  has_neighbors :embedding, normalize: true

  validates :content, presence: true

  before_validation :ensure_account
  after_commit :update_chunk_embedding

  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_assistant, ->(assistant_id) { where(assistant_id: assistant_id) }
  scope :embedded, -> { where.not(embedding: nil) }

  RRF_K = 60

  # Busca híbrida: combina similaridade vetorial (semântica) com full-text (termo exato),
  # fundindo os dois rankings por Reciprocal Rank Fusion. Sem dependência externa.
  # Ponto de extensão: aplicar um reranker (cross-encoder/Cohere) sobre o resultado.
  def self.hybrid_search(query, assistant_id:, account_id: nil, limit: 8, candidates: 30)
    return [] if query.blank?

    scope = by_assistant(assistant_id)
    scope = scope.by_account(account_id) if account_id

    vector_ids   = vector_candidates(scope, query, account_id, candidates)
    fulltext_ids = fulltext_candidates(scope, query, candidates)

    ranked_ids = reciprocal_rank_fusion(vector_ids, fulltext_ids, limit: limit)
    by_id = where(id: ranked_ids).index_by(&:id)
    ranked_ids.filter_map { |id| by_id[id] }
  end

  def self.vector_candidates(scope, query, account_id, candidates)
    embedding = Captain::Llm::EmbeddingService.new(account_id: account_id).get_embedding(query)
    return [] if embedding.blank?

    scope.embedded
         .nearest_neighbors(:embedding, embedding, distance: 'cosine')
         .limit(candidates)
         .pluck(:id)
  rescue Captain::Llm::EmbeddingService::EmbeddingsError => e
    Rails.logger.warn("[DocumentChunk] embedding indisponível na busca: #{e.message}")
    []
  end

  def self.fulltext_candidates(scope, query, candidates)
    scope
      .where("content_search @@ websearch_to_tsquery('simple', ?)", query)
      .order(Arel.sql(sanitize_sql_array(
                        ["ts_rank(content_search, websearch_to_tsquery('simple', ?)) DESC", query]
                      )))
      .limit(candidates)
      .pluck(:id)
  end

  def self.reciprocal_rank_fusion(*ranked_lists, limit:, k: RRF_K)
    scores = Hash.new(0.0)
    ranked_lists.each do |list|
      list.each_with_index { |id, idx| scores[id] += 1.0 / (k + idx + 1) }
    end
    scores.sort_by { |_id, score| -score }.first(limit).map(&:first)
  end

  def embed_text
    contextual_content.presence || content
  end

  private

  def ensure_account
    self.account ||= assistant&.account
  end

  def update_chunk_embedding
    return unless saved_change_to_contextual_content? || saved_change_to_content? || embedding.nil?

    Captain::Llm::UpdateEmbeddingJob.perform_later(self, embed_text)
  end
end
