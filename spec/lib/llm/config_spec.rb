require 'rails_helper'
require 'ostruct'

RSpec.describe Llm::Config do
  let(:account) { create(:account) }
  let(:mock_context) { instance_double(RubyLLM::Context) }
  let(:mock_config) { OpenStruct.new }

  before do
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_ENDPOINT').delete_all
    create(:integrations_hook, :openai, account: account, settings: { api_key: 'sk-test-account-key' })

    allow(RubyLLM).to receive(:context).and_yield(mock_config).and_return(mock_context)
  end

  describe '.context_for_account' do
    it 'uses an OpenAI base endpoint that includes /v1 for default endpoint' do
      described_class.context_for_account(account: account)

      expect(mock_config.openai_api_key).to eq('sk-test-account-key')
      expect(mock_config.openai_api_base).to eq('https://api.openai.com/v1')
    end

    it 'normalizes default endpoint with trailing slash and keeps /v1' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'https://api.openai.com/')

      described_class.context_for_account(account: account)

      expect(mock_config.openai_api_base).to eq('https://api.openai.com/v1')
    end
  end
end
