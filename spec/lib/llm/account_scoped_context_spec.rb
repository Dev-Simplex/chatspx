require 'rails_helper'

RSpec.describe Llm::AccountScopedContext do
  let(:account) { create(:account) }

  before do
    described_class.ruby_llm_context = nil
    described_class.current_account_id = nil
  end

  after do
    described_class.ruby_llm_context = nil
    described_class.current_account_id = nil
  end

  describe '.with_account' do
    it 'sets scoped context and restores previous values after execution' do
      previous_context = instance_double(Object)
      described_class.ruby_llm_context = previous_context
      described_class.current_account_id = 999

      scoped_context = instance_double(Object)
      allow(Llm::Config).to receive(:context_for_account).with(account: account).and_return(scoped_context)

      yielded_context = nil
      described_class.with_account(account) do |context|
        yielded_context = context
        expect(described_class.current_context).to eq(scoped_context)
        expect(described_class.current_account_id).to eq(account.id)
      end

      expect(yielded_context).to eq(scoped_context)
      expect(described_class.current_context).to eq(previous_context)
      expect(described_class.current_account_id).to eq(999)
    end

    it 'cleans scoped values even when the block raises an error' do
      scoped_context = instance_double(Object)
      allow(Llm::Config).to receive(:context_for_account).with(account: account).and_return(scoped_context)

      expect do
        described_class.with_account(account) do
          raise 'boom'
        end
      end.to raise_error('boom')

      expect(described_class.current_context).to be_nil
      expect(described_class.current_account_id).to be_nil
    end
  end

  # O elo que faltava: o runner do gem `ai-agents` cria `RubyLLM::Chat.new(model:)` SEM contexto.
  # Sem o patch instalado no boot, a chave da conta nunca chega ao chat que atende o cliente e tudo
  # roda na chave global da instalação.
  describe 'patch instalado no boot' do
    it 'injects the account context into a Chat created without one' do
      expect(RubyLLM::Chat.ancestors).to include(described_class::ChatThreadContextPatch)

      scoped_context = RubyLLM.context { |config| config.openai_api_key = 'chave-da-conta' }
      allow(Llm::Config).to receive(:context_for_account).with(account: account).and_return(scoped_context)

      chat = described_class.with_account(account) { RubyLLM::Chat.new(model: Llm::Config::DEFAULT_MODEL) }

      expect(chat.instance_variable_get(:@context)).to eq(scoped_context)
      expect(chat.instance_variable_get(:@config).openai_api_key).to eq('chave-da-conta')
    end
  end
end
