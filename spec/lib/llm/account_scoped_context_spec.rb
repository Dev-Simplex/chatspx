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
end
