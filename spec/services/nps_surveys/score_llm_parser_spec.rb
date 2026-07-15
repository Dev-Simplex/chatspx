require 'rails_helper'

RSpec.describe NpsSurveys::ScoreLlmParser do
  let(:account) { create(:account) }
  let(:client) { instance_double(OpenAI::Client) }

  def stub_chat(content)
    allow(OpenAI::Client).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(
      { 'choices' => [{ 'message' => { 'content' => content } }] }
    )
  end

  before do
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').first_or_create!(value: 'test-key')
  end

  describe '#extract' do
    it 'returns nil when text is blank' do
      expect(described_class.extract(text: '', account: account)).to be_nil
    end

    it 'returns nil when no API key is configured' do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').delete_all
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return(nil)
      expect(OpenAI::Client).not_to receive(:new)
      expect(described_class.extract(text: 'dez', account: account)).to be_nil
    end

    it 'extracts an explicit written-out number' do
      stub_chat('{"score": 10}')
      expect(described_class.extract(text: 'dez', account: account)).to eq(10)
    end

    it 'returns nil when the model reports no explicit number (sentiment only)' do
      stub_chat('{"score": null}')
      expect(described_class.extract(text: 'pessimo atendimento', account: account)).to be_nil
    end

    it 'clamps out-of-range values to nil' do
      stub_chat('{"score": 11}')
      expect(described_class.extract(text: 'onze', account: account)).to be_nil
    end

    it 'handles string scores from the model' do
      stub_chat('{"score": "8"}')
      expect(described_class.extract(text: 'uns 8', account: account)).to eq(8)
    end

    it 'returns nil on invalid JSON without raising' do
      stub_chat('not json')
      expect(described_class.extract(text: 'nove', account: account)).to be_nil
    end

    it 'returns nil and does not raise on client error' do
      allow(OpenAI::Client).to receive(:new).and_return(client)
      allow(client).to receive(:chat).and_raise(StandardError, 'boom')
      expect(described_class.extract(text: 'nove', account: account)).to be_nil
    end
  end
end
