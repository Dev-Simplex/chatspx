# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::Models do
  # O spec usava 'gpt-5.1' como representante de "modelo NAO suportado". Isso amarrava o teste
  # ao CONTEUDO do registro: quando o gpt-5.1 passou a ser suportado, os exemplos viraram
  # vermelho sem que a funcao tivesse mudado. O que esta sob teste e o comportamento de
  # `runtime_supported_model?` / `first_runtime_supported`, nao quais modelos existem hoje —
  # entao o nao-suportado passa a ser um nome que nenhum registro vai conter.
  let(:modelo_inexistente) { 'modelo-inexistente-para-teste' }
  let(:outro_inexistente) { 'outro-modelo-inexistente-para-teste' }

  describe '.runtime_supported_model?' do
    it 'returns true for a model supported by current runtime registry' do
      expect(described_class.runtime_supported_model?('gpt-5-mini')).to be(true)
    end

    it 'returns false for a model not supported by current runtime registry' do
      expect(described_class.runtime_supported_model?(modelo_inexistente)).to be(false)
    end
  end

  describe '.first_runtime_supported' do
    it 'returns the first supported model from candidate list' do
      selected = described_class.first_runtime_supported(modelo_inexistente, 'gpt-5-mini', 'gpt-5')
      expect(selected).to eq('gpt-5-mini')
    end

    it 'returns nil when none of the candidates are supported' do
      selected = described_class.first_runtime_supported(modelo_inexistente, outro_inexistente, 'unknown-model')
      expect(selected).to be_nil
    end
  end
end
