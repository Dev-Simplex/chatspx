require 'rails_helper'

# 6.01 — o guardrail de PRÉ-envio. Nenhum exemplo aqui chama IA: o "candidato" é uma
# string que o teste escreve, e as tool calls são a janela em memória.
RSpec.describe Captain::ResponseGuardrailService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def ia_said(content, at: Time.current)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, sender: assistant, content: content, created_at: at)
  end

  def tool(name: 'buscar_imovel', status: 'ok', result_preview: 'Casa A, Casa B', error: nil)
    { tool_name: name, status: status, result_preview: result_preview, error: error }
  end

  describe 'a resposta que nega o que a ferramenta acabou de devolver' do
    subject(:result) do
      described_class.new(conversation: conversation, candidate: 'Não encontrei imóveis com esse perfil.',
                          tool_calls: [tool]).perform
    end

    it 'retains' do
      expect(result.retains?).to be(true)
      expect(result.passes?).to be(false)
    end

    it 'says why, naming the tool' do
      expect(result.reason).to include('buscar_imovel')
      expect(result.findings.first).to include('categoria' => 'contradisse_tool', 'severidade' => 'alta',
                                               'origem' => 'gate')
    end

    # O aceite exige custo zero de LLM. A asserção é sobre a CONTAGEM de chamadas:
    # nenhum serviço de modelo pode ser instanciado dentro do guardrail.
    it 'never calls an LLM' do
      expect(Captain::Llm::AssistantChatService).not_to receive(:new)
      expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)
      expect(Captain::Llm::EmbeddingService).not_to receive(:new)

      result
    end
  end

  describe 'o que NÃO retém' do
    it 'lets an affirmative answer through' do
      result = described_class.new(conversation: conversation, candidate: 'Encontrei 3 imóveis: A, B e C.',
                                   tool_calls: [tool]).perform

      expect(result.passes?).to be(true)
      expect(result.findings).to be_empty
    end

    it 'lets a denial through when the tool itself found nothing' do
      result = described_class.new(conversation: conversation, candidate: 'Não encontrei imóveis com esse perfil.',
                                   tool_calls: [tool(result_preview: 'nenhum resultado')]).perform

      expect(result.passes?).to be(true)
    end

    it 'lets a denial through when no tool ran at all' do
      result = described_class.new(conversation: conversation,
                                   candidate: 'Não encontrei imóveis com esse perfil.', tool_calls: []).perform

      expect(result.passes?).to be(true)
    end

    it 'lets a blank candidate through — silêncio é decisão do agente, não deste gate' do
      expect(described_class.new(conversation: conversation, candidate: '', tool_calls: [tool]).perform.passes?).to be(true)
    end
  end

  describe 'erro de ferramenta: registra, mas NÃO retém' do
    subject(:result) do
      described_class.new(conversation: conversation, candidate: 'O horário é das 9h às 18h.',
                          tool_calls: [tool(status: 'error', result_preview: nil, error: 'Faraday::TimeoutError')]).perform
    end

    it 'passes, because a failed tool does not make the answer false' do
      expect(result.passes?).to be(true)
    end

    it 'still records the finding, at the lower severity' do
      expect(result.findings.first).to include('categoria' => 'ignorou_erro_da_tool', 'severidade' => 'media')
      expect(result.findings.first['porque']).to include('Faraday::TimeoutError')
    end
  end

  describe 'repetição literal do que a IA já enviou' do
    let(:repetida) { 'Posso te ajudar a agendar uma visita, é só me dizer o melhor dia e horário.' }

    it 'retains when the same long text was already sent in the window' do
      ia_said(repetida, at: 2.minutes.ago)

      result = described_class.new(conversation: conversation, candidate: repetida, tool_calls: []).perform

      expect(result.retains?).to be(true)
      expect(result.findings.first['categoria']).to eq('repeticao')
    end

    it 'ignores casing and whitespace, because the visitor sees the same message either way' do
      ia_said(repetida, at: 2.minutes.ago)

      result = described_class.new(conversation: conversation, candidate: "  #{repetida.upcase}\n", tool_calls: []).perform

      expect(result.retains?).to be(true)
    end

    it 'does not retain a short repetition — "Claro!" duas vezes não é bot-loop' do
      ia_said('Claro!', at: 2.minutes.ago)

      expect(described_class.new(conversation: conversation, candidate: 'Claro!', tool_calls: []).perform.passes?).to be(true)
    end

    # A mesma resposta correta, dias depois, para a mesma pergunta repetida, é legítima.
    it 'does not retain outside the lookback window' do
      ia_said(repetida, at: (described_class::REPETITION_LOOKBACK + 5.minutes).ago)

      expect(described_class.new(conversation: conversation, candidate: repetida, tool_calls: []).perform.passes?).to be(true)
    end

    it 'does not look at what a HUMAN agent wrote' do
      agent = create(:user, account: account)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, sender: agent, content: repetida, created_at: 2.minutes.ago)

      expect(described_class.new(conversation: conversation, candidate: repetida, tool_calls: []).perform.passes?).to be(true)
    end

    it 'does not look at another conversation of the same account' do
      outra = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: outra,
                       message_type: :outgoing, sender: assistant, content: repetida, created_at: 2.minutes.ago)

      expect(described_class.new(conversation: conversation, candidate: repetida, tool_calls: []).perform.passes?).to be(true)
    end
  end
end
