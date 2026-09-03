require 'rails_helper'

RSpec.describe Captain::Llm::FaqGeneratorService do
  let(:content) { 'Sample content for FAQ generation' }
  let(:language) { 'english' }
  let(:service) { described_class.new(content, language) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:sample_faqs) do
    [
      { 'question' => 'What is this service?', 'answer' => 'It generates FAQs.' },
      { 'question' => 'How does it work?', 'answer' => 'Using AI technology.' }
    ]
  end
  let(:mock_response) do
    instance_double(RubyLLM::Message, content: { faqs: sample_faqs }.to_json)
  end

  # O servico NAO chama `RubyLLM.chat`: chama `chat` do `Llm::BaseAiService`, que faz
  # `Llm::Config.context_for_account(...).chat(...)`. E a chave nao vem do
  # InstallationConfig global — vem do `Captain::OpenaiHookService` POR CONTA, e este
  # servico e instanciado SEM conta. Por isso mockar `RubyLLM.chat` (e criar o
  # installation_config) nao surtia efeito: o contexto nascia sem chave e o RubyLLM
  # levantava `ConfigurationError`. O mock tem que ficar onde o cliente e construido.
  let(:mock_context) { instance_double(RubyLLM::Context) }

  before do
    allow(Llm::Config).to receive(:context_for_account).and_return(mock_context)
    allow(mock_context).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  describe '#generate' do
    context 'when successful' do
      it 'returns parsed FAQs from the LLM response' do
        result = service.generate
        expect(result).to eq(sample_faqs)
      end

      it 'sends content to LLM with JSON response format' do
        expect(mock_chat).to receive(:with_params).with(response_format: { type: 'json_object' }).and_return(mock_chat)
        service.generate
      end

      it 'uses SystemPromptsService with the specified language' do
        expect(Captain::Llm::SystemPromptsService).to receive(:faq_generator).with(language).at_least(:once).and_call_original
        service.generate
      end
    end

    context 'with different language' do
      let(:language) { 'spanish' }

      it 'passes the correct language to SystemPromptsService' do
        expect(Captain::Llm::SystemPromptsService).to receive(:faq_generator).with('spanish').at_least(:once).and_call_original
        service.generate
      end
    end

    context 'when LLM API fails' do
      before do
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new(nil, 'API Error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns empty array and logs the error' do
        expect(Rails.logger).to receive(:error).with('LLM API Error: API Error')
        expect(service.generate).to eq([])
      end
    end

    context 'when response content is nil' do
      let(:nil_response) { instance_double(RubyLLM::Message, content: nil) }

      before do
        allow(mock_chat).to receive(:ask).and_return(nil_response)
      end

      it 'returns empty array' do
        expect(service.generate).to eq([])
      end
    end

    context 'when JSON parsing fails' do
      let(:invalid_response) { instance_double(RubyLLM::Message, content: 'invalid json') }

      before do
        allow(mock_chat).to receive(:ask).and_return(invalid_response)
      end

      it 'logs error and returns empty array' do
        expect(Rails.logger).to receive(:error).with(/Error in parsing GPT processed response:/)
        expect(service.generate).to eq([])
      end
    end

    context 'when response is missing faqs key' do
      let(:missing_key_response) { instance_double(RubyLLM::Message, content: '{"data": []}') }

      before do
        allow(mock_chat).to receive(:ask).and_return(missing_key_response)
      end

      it 'returns empty array via KeyError rescue' do
        expect(service.generate).to eq([])
      end
    end
  end
end
