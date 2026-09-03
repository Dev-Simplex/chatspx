require 'rails_helper'

# 6.03 — a citação vira metadado da mensagem, persistido.
#
# NENHUMA IA É CHAMADA. O gerador é um dublê que, quando o caso pede, empurra a fonte
# para a janela — que é o que a ferramenta de busca real faz ao rodar dentro da geração.
RSpec.describe Captain::Conversation::ResponseBuilderJob, type: :job do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, status: :pending,
                          assignee_agent_bot: assistant.mirror_agent_bot)
  end
  let(:mock_llm_chat_service) { instance_double(Captain::Llm::AssistantChatService) }
  let(:mock_action_classifier_service) { instance_double(Captain::Llm::AssistantActionClassifierService) }
  let(:mock_false_promise_service) { instance_double(Captain::Llm::AssistantFalsePromiseService) }
  let(:fonte) { { title: 'Política de trocas', source: 'https://exemplo.com/trocas', excerpt: 'Troca em 30 dias.' } }

  def stub_generation(content, citation: nil)
    allow(mock_llm_chat_service).to receive(:generate_response) do
      Captain::CitationWindow.record(**citation) if citation
      { 'response' => content }
    end
  end

  before do
    create(:message, conversation: conversation, content: 'Posso trocar?', message_type: :incoming)

    allow(inbox).to receive(:captain_active?).and_return(true)
    allow(account).to receive(:feature_enabled?).and_return(false)
    allow(Captain::Llm::AssistantChatService).to receive(:new).and_return(mock_llm_chat_service)
    allow(Captain::Llm::AssistantActionClassifierService).to receive(:new).and_return(mock_action_classifier_service)
    allow(mock_action_classifier_service).to receive(:classify).and_return({ 'action' => 'continue' })
    allow(Captain::Llm::AssistantFalsePromiseService).to receive(:new).and_return(mock_false_promise_service)
    allow(mock_false_promise_service).to receive(:detect).and_return({ 'decision' => 'safe', 'reason' => 'safe_response' })
  end

  describe 'a resposta baseada em documento' do
    before { stub_generation('Você tem 30 dias para trocar.', citation: fonte) }

    it 'shows where it came from' do
      described_class.perform_now(conversation, assistant)

      citations = conversation.messages.outgoing.last.content_attributes['citations']
      expect(citations.first['title']).to eq('Política de trocas')
      expect(citations.first['url']).to eq('https://exemplo.com/trocas')
    end

    # "Sobrevive ao reload" = está no banco, não na renderização. Aqui se lê de novo do
    # banco, com uma instância nova, sem nada em memória.
    it 'survives the reload, because it is in the database' do
      described_class.perform_now(conversation, assistant)
      Captain::CitationWindow.close!

      message = Message.find(conversation.messages.outgoing.last.id)
      expect(message.content_attributes['citations'].first['title']).to eq('Política de trocas')
    end
  end

  describe 'o que NÃO ganha citação' do
    it 'an answer with no retrieval behind it' do
      stub_generation('Claro, posso ajudar com isso.')

      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.last.content_attributes['citations']).to be_nil
    end

    # Exibir "fonte: X" embaixo de "não encontrei" é incoerente, e ensina o visitante a
    # desconfiar da referência justamente quando ela está certa.
    it 'an answer that denies having found anything' do
      stub_generation('Não encontrei nada sobre isso na nossa política.', citation: fonte)

      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.last.content_attributes['citations']).to be_nil
    end

    it 'the handoff message' do
      stub_generation('conversation_handoff', citation: fonte)

      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.last.content_attributes['citations']).to be_nil
    end
  end

  # Numa rajada, a citação é rodapé da resposta INTEIRA — vai na última bolha, não
  # repetida em cada pedaço.
  describe 'quando a resposta sai picada (humanizer)' do
    before do
      assistant.update!(behavior: { 'humanizer' => { 'enabled' => true, 'min_delay_s' => 0, 'max_delay_s' => 0,
                                                     'delay_ms' => 0, 'delay_per_char_ms' => 0 } })
      stub_generation("Você tem 30 dias para trocar.\n\nQuer que eu abra o pedido?", citation: fonte)
    end

    it 'puts the citation on the last bubble only' do
      described_class.perform_now(conversation, assistant)

      bolhas = conversation.messages.outgoing.reorder(:id).to_a
      expect(bolhas.size).to eq(2)
      expect(bolhas.first.content_attributes['citations']).to be_nil
      expect(bolhas.last.content_attributes['citations'].first['title']).to eq('Política de trocas')
    end
  end

  describe 'a janela de citações' do
    it 'is closed after the job' do
      stub_generation('Você tem 30 dias para trocar.', citation: fonte)

      described_class.perform_now(conversation, assistant)

      expect(Captain::CitationWindow.open?).to be(false)
      expect(Captain::CitationWindow.citations).to eq([])
    end
  end
end
