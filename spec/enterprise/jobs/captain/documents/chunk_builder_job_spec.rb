require 'rails_helper'

RSpec.describe Captain::Documents::ChunkBuilderJob do
  let(:account) { create(:account) }
  let(:assistant) do
    create(:captain_assistant, account: account, config: { 'knowledge_mode' => 'hybrid', 'contextual_chunks' => false })
  end
  let(:document) do
    create(:captain_document, assistant: assistant, account: account, content: "parágrafo um\n\nparágrafo dois")
  end

  before do
    allow(Captain::Llm::DocumentChunkingService).to receive(:new)
      .and_return(instance_double(Captain::Llm::DocumentChunkingService, chunks: %w[chunk-um chunk-dois]))
  end

  it 'creates one DocumentChunk per piece when chunk knowledge is enabled' do
    expect { described_class.perform_now(document) }
      .to change { document.document_chunks.count }.from(0).to(2)
    expect(document.document_chunks.order(:position).pluck(:content)).to eq(%w[chunk-um chunk-dois])
  end

  it 'skips when knowledge_mode is faq only' do
    assistant.update!(config: { 'knowledge_mode' => 'faq' })
    expect { described_class.perform_now(document) }.not_to(change { document.document_chunks.count })
  end

  it 'skips when content is blank' do
    document.update_column(:content, nil)
    expect { described_class.perform_now(document) }.not_to(change { document.document_chunks.count })
  end

  it 'resets previous chunks before rebuilding' do
    create(:captain_document_chunk, document: document, assistant: assistant, account: account, content: 'velho')
    described_class.perform_now(document)
    expect(document.document_chunks.reload.pluck(:content)).to match_array(%w[chunk-um chunk-dois])
  end

  it 'does not call the contextual service when contextual_chunks is disabled' do
    expect(Captain::Llm::ContextualChunkService).not_to receive(:new)
    described_class.perform_now(document)
  end
end
