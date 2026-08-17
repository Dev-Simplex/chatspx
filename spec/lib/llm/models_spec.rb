# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::Models do
  describe '.providers' do
    it 'loads provider metadata from the config' do
      expect(described_class.providers).to include(
        'openai' => include('display_name' => 'OpenAI')
      )
    end
  end

  describe '.features' do
    it 'keeps every feature default in the allowed model list' do
      described_class.features.each do |feature_key, config|
        expect(config['models']).to include(config['default']), "#{feature_key} default model must be allowed"
      end
    end

    it 'references existing models from every feature' do
      described_class.features.each do |feature_key, config|
        missing_models = config['models'].reject { |model_name| described_class.models.key?(model_name) }

        expect(missing_models).to be_empty, "#{feature_key} references missing models: #{missing_models.join(', ')}"
      end
    end

    it 'routes each FAQ operation independently' do
      expect(described_class.default_model_for('document_faq_generation')).to eq('gpt-4.1-mini')
      expect(described_class.default_model_for('conversation_faq_generation')).to eq('gpt-5-mini')
      expect(described_class.default_model_for('conversation_faq_matching')).to eq('gpt-4.1-mini')
    end
  end

  describe '.models' do
    it 'references existing providers from every model' do
      missing_providers = described_class.models.filter_map do |model_name, config|
        provider = config['provider']
        next if described_class.providers.key?(provider)

        "#{model_name}: #{provider}"
      end

      expect(missing_providers).to be_empty
    end
  end

  describe '.feature_config' do
    it 'returns model metadata for a feature' do
      config = described_class.feature_config('editor')

      expect(config[:default]).to eq('gpt-4.1-mini')
      expect(config[:models].first).to include(
        id: 'gpt-4.1-mini',
        display_name: 'GPT-4.1 Mini',
        provider: 'openai',
        credit_multiplier: 1
      )
    end
  end

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
