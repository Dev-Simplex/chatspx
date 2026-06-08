require 'rails_helper'

RSpec.describe Captain::Llm::DocumentChunkingService do
  describe '#chunks' do
    it 'returns empty array for blank content' do
      expect(described_class.new('').chunks).to eq([])
      expect(described_class.new("   \n\n ").chunks).to eq([])
    end

    it 'keeps short content as a single chunk' do
      content = 'Uma frase curta sobre a Tozi.'
      chunks = described_class.new(content).chunks
      expect(chunks.size).to eq(1)
      expect(chunks.first).to include('Tozi')
    end

    it 'splits long content into multiple chunks respecting the size limit' do
      paragraph = (['Frase de teste com algum conteúdo relevante.'] * 8).join(' ')
      content = ([paragraph] * 10).join("\n\n")
      chunks = described_class.new(content, chunk_size: 300, overlap: 40).chunks

      expect(chunks.size).to be > 1
      expect(chunks).to all(satisfy { |c| c.length <= 300 + 40 })
    end

    it 'applies overlap between consecutive chunks' do
      units = (1..20).map { |i| "Parágrafo número #{i} com texto suficiente para encher." }
      content = units.join("\n\n")
      chunks = described_class.new(content, chunk_size: 120, overlap: 30).chunks

      expect(chunks.size).to be > 1
      # algum trecho do fim de um chunk reaparece no começo do próximo
      overlap_found = chunks.each_cons(2).any? do |a, b|
        tail = a[-20..] || a
        b.include?(tail.split.last.to_s)
      end
      expect(overlap_found).to be(true)
    end

    it 'hard-splits a single oversized sentence without separators' do
      content = 'x' * 2500
      chunks = described_class.new(content, chunk_size: 500, overlap: 0).chunks
      expect(chunks.size).to be >= 5
      expect(chunks).to all(satisfy { |c| c.length <= 500 })
    end
  end
end
