require 'rails_helper'

RSpec.describe Copilot::StreamingChatService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }
  let(:chunks) { ['Bom ', 'dia, ', 'agente!'] }
  let(:llm) { stub_copilot_llm(chunks: chunks, account: account) }

  before { create(:integrations_hook, :openai, account: account, settings: { api_key: 'test-account-key' }) }

  def add_message(content, type)
    create(:captain_copilot_message, account: account, copilot_thread: copilot_thread,
                                     message: { content: content }, message_type: type)
  end

  describe '#call' do
    before do
      llm
      add_message('Resume a conversa', :user)
    end

    it 'entrega os deltas na ordem em que o provedor emitiu' do
      received = []
      result = described_class.new(copilot_thread: copilot_thread).call { |delta| received << delta }

      expect(received).to eq(chunks)
      expect(result).to eq('Bom dia, agente!')
    end

    it 'manda o historico anterior e pergunta a ultima mensagem do agente' do
      add_message('Bom dia', :assistant)
      add_message('E agora?', :user)

      described_class.new(copilot_thread: copilot_thread).call

      expect(llm[:chat]).to have_received(:add_message).with(role: :user, content: 'Resume a conversa')
      expect(llm[:chat]).to have_received(:add_message).with(role: :assistant, content: 'Bom dia')
      expect(llm[:chat]).to have_received(:ask).with('E agora?')
    end

    it 'nao chama o provedor quando nao ha pergunta pendente' do
      add_message('Ja respondi', :assistant)

      expect(described_class.new(copilot_thread: copilot_thread).call).to eq('')
      expect(llm[:chat]).not_to have_received(:ask)
    end

    it 'aperta o timeout de rede e o retry do provedor no contexto da geracao' do
      described_class.new(copilot_thread: copilot_thread).call

      expect(llm[:context].config.request_timeout).to eq(described_class::REQUEST_TIMEOUT_SECONDS)
      expect(llm[:context].config.max_retries).to eq(described_class::MAX_RETRIES)
    end
  end

  describe '#call com cancelamento' do
    before do
      llm
      add_message('Resume a conversa', :user)
    end

    it 'para a geracao no chunk seguinte ao cancelamento' do
      received = []
      cancelled = false

      expect do
        described_class.new(copilot_thread: copilot_thread).call(cancelled: -> { cancelled }) do |delta|
          received << delta
          cancelled = true
        end
      end.to raise_error(described_class::Cancelled)

      expect(received).to eq(['Bom '])
    end
  end

  describe '#call com falha do provedor' do
    before { add_message('Resume a conversa', :user) }

    it 'traduz o 401 num StreamingError com codigo estavel' do
      stub_copilot_llm(error: RubyLLM::UnauthorizedError.new(nil, 'Incorrect API key provided: sk-proj-abcdef123456'),
                       account: account)

      expect { described_class.new(copilot_thread: copilot_thread).call }.to raise_error(Copilot::StreamingError) do |error|
        expect(error.code).to eq('unauthorized')
        expect(error.message).not_to include('sk-proj')
      end
    end

    it 'traduz erro inesperado em internal' do
      stub_copilot_llm(error: StandardError.new('boom'), account: account)

      expect { described_class.new(copilot_thread: copilot_thread).call }.to raise_error(Copilot::StreamingError) do |error|
        expect(error.code).to eq('internal')
      end
    end
  end

  describe 'contexto da conversa' do
    let(:conversation) { create(:conversation, account: account) }

    before do
      llm
      add_message('Resume a conversa', :user)
    end

    it 'inclui a transcricao da conversa que o agente esta olhando' do
      create(:message, account: account, conversation: conversation, content: 'Meu pedido nao chegou', message_type: :incoming)
      create(:message, account: account, conversation: conversation, content: 'Vou verificar', message_type: :outgoing)

      described_class.new(copilot_thread: copilot_thread, conversation_id: conversation.display_id).call

      expect(llm[:chat]).to have_received(:with_instructions) do |instructions|
        expect(instructions).to include('Customer: Meu pedido nao chegou')
        expect(instructions).to include('Agent: Vou verificar')
      end
    end

    it 'nao quebra quando a conversa nao existe' do
      expect { described_class.new(copilot_thread: copilot_thread, conversation_id: 999_999).call }.not_to raise_error
    end
  end
end
