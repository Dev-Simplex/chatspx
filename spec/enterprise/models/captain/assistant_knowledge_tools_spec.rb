require 'rails_helper'

# CHAT-168: faq_lookup e search_knowledge eram injetados em todo agente, mesmo sem nada para buscar.
# Na conta 6, cinco agentes sem documento chamaram search_knowledge 18 vezes em 30 dias, e todas
# voltaram vazias. A ferramenta de busca só entra quando o modo de conhecimento a prevê e há conteúdo.
RSpec.describe Captain::Assistant do
  let(:account) { create(:account) }

  def ferramentas(assistant)
    assistant.send(:agent_tools).map(&:class)
  end

  describe 'faq_lookup' do
    let(:assistant) { create(:captain_assistant, account: account) }

    it 'fica de fora sem FAQ aprovada' do
      create(:captain_assistant_response, assistant: assistant, account: account, status: :pending)

      expect(ferramentas(assistant)).not_to include(Captain::Tools::FaqLookupTool)
    end

    it 'entra com FAQ aprovada' do
      create(:captain_assistant_response, assistant: assistant, account: account)

      expect(ferramentas(assistant)).to include(Captain::Tools::FaqLookupTool)
    end

    it 'fica de fora no modo só-documentos, mesmo com FAQ' do
      assistant.update!(config: { 'knowledge_mode' => 'chunks' })
      create(:captain_assistant_response, assistant: assistant, account: account)

      expect(ferramentas(assistant)).not_to include(Captain::Tools::FaqLookupTool)
    end
  end

  describe 'search_knowledge' do
    let(:assistant) { create(:captain_assistant, account: account, config: { 'knowledge_mode' => 'hybrid' }) }

    it 'fica de fora sem documento indexado' do
      expect(ferramentas(assistant)).not_to include(Captain::Tools::SearchKnowledgeTool)
    end

    it 'entra com documento indexado' do
      create(:captain_document_chunk, assistant: assistant, account: account)

      expect(ferramentas(assistant)).to include(Captain::Tools::SearchKnowledgeTool)
    end

    it 'fica de fora no modo só-FAQ, mesmo com documento' do
      assistant.update!(config: { 'knowledge_mode' => 'faq' })
      create(:captain_document_chunk, assistant: assistant, account: account)

      expect(ferramentas(assistant)).not_to include(Captain::Tools::SearchKnowledgeTool)
    end
  end

  it 'mantém o handoff sempre' do
    expect(ferramentas(create(:captain_assistant, account: account))).to include(Captain::Tools::HandoffTool)
  end
end
