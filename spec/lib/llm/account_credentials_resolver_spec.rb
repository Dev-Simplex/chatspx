require 'rails_helper'

RSpec.describe Llm::AccountCredentialsResolver do
  let(:account) { create(:account) }

  describe '#openai_api_base' do
    before do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_ENDPOINT').delete_all
    end

    it 'uses /v1 for the default OpenAI endpoint' do
      resolver = described_class.new(account: account)

      expect(resolver.openai_api_base).to eq('https://api.openai.com/v1')
    end

    it 'does not force /v1 for custom endpoints' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'https://llm-proxy.internal')
      resolver = described_class.new(account: account)

      expect(resolver.openai_api_base).to eq('https://llm-proxy.internal')
    end

    it 'normalizes trailing slash on the default endpoint' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'https://api.openai.com/')
      resolver = described_class.new(account: account)

      expect(resolver.openai_api_base).to eq('https://api.openai.com/v1')
    end
  end
end
