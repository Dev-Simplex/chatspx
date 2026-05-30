class CreateCaptainDocumentChunks < ActiveRecord::Migration[7.1]
  # Sem transacao DDL: o fallback HNSW->ivfflat (add_vector_index) faz rescue de
  # uma falha de add_index. Dentro de transacao, o erro do HNSW abortaria toda a
  # transacao (PG::InFailedSqlTransaction) e o fallback nao rodaria. Fora dela,
  # cada statement commita isolado e o rescue funciona.
  disable_ddl_transaction!

  def up
    create_table :captain_document_chunks, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.bigint :assistant_id, null: false
      t.bigint :captain_document_id, null: false
      t.integer :position, null: false, default: 0
      t.text :content, null: false
      # contextual_content = content + contexto gerado por LLM (Anthropic contextual retrieval).
      # É o que vai pro embedding; content puro alimenta o full-text.
      t.text :contextual_content
      t.vector :embedding, limit: 1536
      # full-text gerado (language-agnostic 'simple' p/ multi-tenant). GIN abaixo.
      t.virtual :content_search, type: :tsvector,
                                 as: "to_tsvector('simple', coalesce(content, ''))", stored: true
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :captain_document_chunks, :account_id, if_not_exists: true
    add_index :captain_document_chunks, :assistant_id, if_not_exists: true
    add_index :captain_document_chunks, :captain_document_id, name: 'idx_cap_doc_chunks_on_document', if_not_exists: true
    add_index :captain_document_chunks, :content_search, using: :gin, name: 'idx_cap_doc_chunks_fulltext', if_not_exists: true

    add_vector_index
  end

  def down
    drop_table :captain_document_chunks
  end

  private

  # HNSW (pgvector >= 0.5) tem recall/latência melhores que ivfflat.
  # Fallback p/ ivfflat se a versão instalada não suportar HNSW.
  def add_vector_index
    add_index :captain_document_chunks, :embedding,
              using: :hnsw, opclass: :vector_cosine_ops,
              name: 'idx_cap_doc_chunks_embedding_hnsw', if_not_exists: true
  rescue StandardError => e
    Rails.logger.warn("[CreateCaptainDocumentChunks] HNSW indisponível (#{e.message}); usando ivfflat")
    execute <<~SQL.squish
      CREATE INDEX IF NOT EXISTS idx_cap_doc_chunks_embedding_ivfflat
      ON captain_document_chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
    SQL
  end
end
