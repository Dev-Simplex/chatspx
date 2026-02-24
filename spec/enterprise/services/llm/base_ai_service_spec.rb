# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::BaseAiService do
  let(:service_class) do
    Class.new(described_class) do
      private

      def feature_name
        'copilot'
      end
    end
  end

  let(:account_class) { Struct.new(:id, :captain_copilot_model) }

  describe 'model resolution fallback' do
    before do
      allow(Rails.logger).to receive(:warn)
    end

    it 'uses configured model when it is runtime supported' do
      account = account_class.new(3, 'gpt-5-mini')
      service = service_class.new(account: account)

      expect(service.model).to eq('gpt-5-mini')
      expect(Rails.logger).not_to have_received(:warn)
    end

    it 'falls back to feature default when configured model is unsupported' do
      account = account_class.new(3, 'gpt-5.1')
      service = service_class.new(account: account)

      expect(service.model).to eq('gpt-5-mini')
      expect(Rails.logger).to have_received(:warn).with(
        include('feature_name=copilot', 'invalid_model=gpt-5.1', 'fallback_model=gpt-5-mini')
      )
    end

    it 'falls back to global default when configured and feature default are unsupported' do
      allow(Llm::Models).to receive(:default_model_for).and_call_original
      allow(Llm::Models).to receive(:default_model_for).with('copilot').and_return('gpt-5.2')

      account = account_class.new(3, 'gpt-5.1')
      service = service_class.new(account: account)

      expect(service.model).to eq(Llm::Config::DEFAULT_MODEL)
      expect(Rails.logger).to have_received(:warn).with(
        include('feature_name=copilot', 'invalid_model=gpt-5.1', "fallback_model=#{Llm::Config::DEFAULT_MODEL}")
      )
      expect(Rails.logger).to have_received(:warn).with(
        include('feature_name=copilot', 'invalid_model=gpt-5.2', "fallback_model=#{Llm::Config::DEFAULT_MODEL}")
      )
    end
  end
end
