require 'rails_helper'

RSpec.describe Captain::DocumentChunk do
  describe '.reciprocal_rank_fusion' do
    it 'favors items ranked high in both lists' do
      vector = %w[a b c d]
      fulltext = %w[c a e f]
      result = described_class.reciprocal_rank_fusion(vector, fulltext, limit: 3)
      # 'a' (pos 0 e 1) e 'c' (pos 2 e 0) aparecem nas duas listas -> topo
      expect(result.first(2)).to contain_exactly('a', 'c')
    end

    it 'handles disjoint lists' do
      result = described_class.reciprocal_rank_fusion(%w[a b], %w[c d], limit: 4)
      expect(result).to contain_exactly('a', 'b', 'c', 'd')
    end

    it 'respects the limit' do
      result = described_class.reciprocal_rank_fusion(%w[a b c d e], %w[e d c b a], limit: 2)
      expect(result.size).to eq(2)
    end

    it 'returns empty for empty inputs' do
      expect(described_class.reciprocal_rank_fusion([], [], limit: 5)).to eq([])
    end
  end

  describe '.hybrid_search' do
    let(:assistant) { create(:captain_assistant) }

    it 'returns empty array for blank query' do
      expect(described_class.hybrid_search('', assistant_id: assistant.id)).to eq([])
    end
  end

  describe 'embedding callback' do
    it 'enqueues embedding job using contextual_content when present' do
      chunk = build(:captain_document_chunk, content: 'puro', contextual_content: 'contexto\n\npuro')
      expect(Captain::Llm::UpdateEmbeddingJob).to receive(:perform_later).with(chunk, chunk.embed_text)
      chunk.save!
    end

    it 'embed_text falls back to content when no contextual_content' do
      chunk = build(:captain_document_chunk, content: 'só conteúdo', contextual_content: nil)
      expect(chunk.embed_text).to eq('só conteúdo')
    end
  end
end
