require 'rails_helper'

# 6.03 — a fonte que já ia como prosa passa a ir também como DADO.
RSpec.describe Captain::Tools::SearchKnowledgeTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  def chunk_duplo(metadata, content)
    # `format_chunk` le `contextual_content.presence || content`: sem este stub o
    # instance_double recusa a mensagem e derruba o teste. nil = cai no conteudo puro,
    # que e o caso de conta sem contextual retrieval.
    instance_double(Captain::DocumentChunk, metadata: metadata, content: content, id: 1, contextual_content: nil)
  end

  before { Captain::CitationWindow.open! }
  after { Captain::CitationWindow.close! }

  context 'when the search finds passages' do
    before do
      allow(Captain::DocumentChunk).to receive(:hybrid_search).and_return(
        [chunk_duplo({ 'name' => 'Política de trocas', 'source' => 'https://exemplo.com/trocas' }, 'Troca em 30 dias.')]
      )
    end

    it 'keeps sending the source as prose to the model — o prompt não mudou' do
      resultado = tool.perform(tool_context, query: 'troca')

      expect(resultado).to include('Troca em 30 dias.')
      expect(resultado).to include('(fonte: Política de trocas)')
    end

    it 'also records the source as data, with the document and the excerpt' do
      tool.perform(tool_context, query: 'troca')

      expect(Captain::CitationWindow.citations).to eq(
        [{ 'title' => 'Política de trocas', 'url' => 'https://exemplo.com/trocas', 'excerpt' => 'Troca em 30 dias.' }]
      )
    end
  end

  context 'when the search finds nothing' do
    before { allow(Captain::DocumentChunk).to receive(:hybrid_search).and_return([]) }

    it 'records no citation — sem recuperação não há o que citar' do
      resultado = tool.perform(tool_context, query: 'troca')

      expect(resultado).to include('No relevant knowledge found')
      expect(Captain::CitationWindow.citations).to be_empty
    end
  end

  # Falha ao registrar a fonte não pode derrubar a busca.
  it 'still answers when recording the citation blows up' do
    allow(Captain::DocumentChunk).to receive(:hybrid_search).and_return(
      [chunk_duplo({ 'name' => 'Política' }, 'texto')]
    )
    allow(Captain::CitationWindow).to receive(:record).and_raise(StandardError, 'boom')

    expect { tool.perform(tool_context, query: 'troca') }.not_to raise_error
  end
end
