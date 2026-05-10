require 'rails_helper'

RSpec.describe Captain::SentimentAnalysisService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:service) { described_class.new(account: account, conversation_display_id: conversation.display_id) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_context) { instance_double(RubyLLM::Context, chat: mock_chat) }
  let(:mock_response) { instance_double(RubyLLM::Message, content: '**Tom detectado**: neutro', input_tokens: 10, output_tokens: 5) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(Llm::Config).to receive(:with_api_key).and_yield(mock_context)
    allow(mock_chat).to receive(:with_instructions)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
  end

  describe '#perform' do
    it 'sends sentiment_analysis prompt as system message' do
      create(:message, conversation: conversation, message_type: :incoming, content: 'estou muito chateado')

      expect(service).to receive(:make_api_call) do |args|
        expect(args[:messages][0][:role]).to eq('system')
        expect(args[:messages][0][:content]).to include('Cliente: estou muito chateado')
        { message: 'Tom: frustrado' }
      end

      service.perform
    end

    it 'filters out private messages from the prompt' do
      create(:message, conversation: conversation, message_type: :incoming, content: 'mensagem publica')
      create(:message, conversation: conversation, message_type: :outgoing, content: 'NOTA SECRETA', private: true)

      expect(service).to receive(:make_api_call) do |args|
        expect(args[:messages][0][:content]).to include('mensagem publica')
        expect(args[:messages][0][:content]).not_to include('NOTA SECRETA')
        { message: 'Tom: neutro' }
      end

      service.perform
    end

    it 'redacts PII from messages before injecting into the prompt' do
      create(:message, conversation: conversation, message_type: :incoming, content: 'meu CPF é 123.456.789-09')

      expect(service).to receive(:make_api_call) do |args|
        expect(args[:messages][0][:content]).to include('[CPF]')
        expect(args[:messages][0][:content]).not_to include('123.456.789-09')
        { message: 'Tom: neutro' }
      end

      service.perform
    end

    it 'returns formatted response from the LLM' do
      create(:message, conversation: conversation, message_type: :incoming, content: 'estou bem')
      result = service.perform
      expect(result[:message]).to eq('**Tom detectado**: neutro')
    end

    it 'handles empty conversation gracefully' do
      expect(service).to receive(:make_api_call) do |args|
        expect(args[:messages][0][:content]).to be_a(String)
        { message: 'neutro' }
      end

      service.perform
    end
  end
end
