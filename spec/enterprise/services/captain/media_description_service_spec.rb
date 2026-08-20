require 'rails_helper'

RSpec.describe Captain::MediaDescriptionService, type: :service do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, message_type: :incoming) }
  let(:attachment) do
    message.attachments.create!(account: account, file_type: :image, external_url: 'https://example.com/foto.jpg')
  end

  let(:openai_client) { instance_double(OpenAI::Client) }
  let(:ok_response) do
    { 'choices' => [{ 'message' => { 'content' => 'Uma folha de papel impressa sobre uma mesa.' } }],
      'usage' => { 'prompt_tokens' => 10, 'completion_tokens' => 20 } }
  end

  before do
    account.update!(openai_api_key: 'sk-conta')
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:chat).and_return(ok_response)
  end

  describe '#perform' do
    it 'describes the image and caches the text on the attachment' do
      expect(described_class.new(attachment: attachment).perform).to eq('Uma folha de papel impressa sobre uma mesa.')
      expect(attachment.reload.meta[described_class::META_KEY]).to eq('Uma folha de papel impressa sobre uma mesa.')
    end

    it 'resolves the key from the account, not from the installation config' do
      expect(OpenAI::Client).to receive(:new).with(access_token: 'sk-conta').and_return(openai_client)

      described_class.new(attachment: attachment).perform
    end

    it 'falls back to the environment key when the account has none' do
      account.update!(openai_api_key: nil)
      expect(OpenAI::Client).to receive(:new).with(access_token: 'sk-env').and_return(openai_client)

      with_modified_env OPENAI_API_KEY: 'sk-env' do
        described_class.new(attachment: attachment).perform
      end
    end

    it 'uses the per-account vision model when configured' do
      account.update!(openai_model_vision: 'gpt-4o')
      described_class.new(attachment: attachment).perform

      expect(openai_client).to have_received(:chat).with(hash_including(parameters: hash_including(model: 'gpt-4o')))
    end

    it 'reuses the cached description without calling the model again' do
      attachment.update!(meta: { described_class::META_KEY => 'descricao ja gravada' })

      expect(described_class.new(attachment: attachment).perform).to eq('descricao ja gravada')
      expect(openai_client).not_to have_received(:chat)
    end

    it 'ignores attachment types the layer does not handle yet' do
      video = message.attachments.create!(account: account, file_type: :video, external_url: 'https://example.com/v.mp4')

      expect(described_class.new(attachment: video).perform).to be_nil
      expect(openai_client).not_to have_received(:chat)
    end

    context 'when the key is missing' do
      it 'skips with a visible warning instead of calling the model' do
        account.update!(openai_api_key: nil)
        allow(Rails.logger).to receive(:warn)

        with_modified_env OPENAI_API_KEY: nil do
          expect(described_class.new(attachment: attachment).perform).to be_nil
        end

        expect(Rails.logger).to have_received(:warn).with(/MediaDescription.*sem chave OpenAI/)
        expect(openai_client).not_to have_received(:chat)
      end
    end

    context 'when the model fails' do
      before do
        allow(openai_client).to receive(:chat).and_raise(Faraday::ServerError.new('boom'))
      end

      it 'degrades to no description instead of raising' do
        expect { described_class.new(attachment: attachment).perform }.not_to raise_error
        expect(attachment.reload.meta[described_class::META_KEY]).to be_nil
      end

      it 'logs the failure visibly and reports it to the exception tracker' do
        tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
        allow(Rails.logger).to receive(:error)

        described_class.new(attachment: attachment).perform

        expect(Rails.logger).to have_received(:error).with(/MediaDescription. FALHOU att=#{attachment.id}/)
        expect(tracker).to have_received(:capture_exception)
      end
    end
  end
end
