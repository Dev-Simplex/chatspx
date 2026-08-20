# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::Models do
  describe '.runtime_supported_model?' do
    it 'returns true for a model supported by current runtime registry' do
      expect(described_class.runtime_supported_model?('gpt-5-mini')).to be(true)
    end

    it 'returns false for a model not supported by current runtime registry' do
      expect(described_class.runtime_supported_model?('gpt-5.1')).to be(false)
    end
  end

  describe '.first_runtime_supported' do
    it 'returns the first supported model from candidate list' do
      selected = described_class.first_runtime_supported('gpt-5.1', 'gpt-5-mini', 'gpt-5')
      expect(selected).to eq('gpt-5-mini')
    end

    it 'returns nil when none of the candidates are supported' do
      selected = described_class.first_runtime_supported('gpt-5.1', 'gpt-5.2', 'unknown-model')
      expect(selected).to be_nil
    end
  end
end
