require 'rails_helper'
# explicitly requiring since we are loading apms conditionally in application.rb
require 'sentry-ruby'

describe ChatwootExceptionTracker do
  it 'use rails logger if no tracker is configured' do
    # O exemplo PRESSUPOE que nao ha tracker, mas nunca estabelecia isso: `capture_exception`
    # decide por `ENV['SENTRY_DSN'].present?`, e esta VM tem o DSN preenchido (GlitchTip). Onde a
    # variavel existe, o caminho do Sentry rodava e o exemplo falhava com
    # `ArgumentError: expect the argument to be a Exception, got String`.
    # Passava so em maquina sem observabilidade configurada — o oposto de producao.
    with_modified_env SENTRY_DSN: nil do
      expect(Rails.logger).to receive(:error).with('random')
      described_class.new('random').capture_exception
    end
  end

  context 'with sentry DSN' do
    before do
      # since sentry is not initated in test, we need to do it manually
      Sentry.init do |config|
        config.dsn = 'test'
      end
    end

    it 'will call sentry capture exception' do
      with_modified_env SENTRY_DSN: 'random dsn' do
        expect(Sentry).to receive(:capture_exception).with('random')
        described_class.new('random').capture_exception
      end
    end
  end
end
