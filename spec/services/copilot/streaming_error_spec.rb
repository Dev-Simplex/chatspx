require 'rails_helper'

RSpec.describe Copilot::StreamingError do
  describe '.from' do
    it 'traduz 401 do provedor em unauthorized' do
      error = described_class.from(RubyLLM::UnauthorizedError.new(nil, 'Incorrect API key provided: sk-proj-abcdef123456'))

      expect(error.code).to eq('unauthorized')
    end

    it 'traduz 429 do provedor em rate_limited' do
      expect(described_class.from(RubyLLM::RateLimitError.new(nil, 'slow down')).code).to eq('rate_limited')
    end

    it 'traduz indisponibilidade do provedor em provider_down' do
      expect(described_class.from(RubyLLM::ServiceUnavailableError.new(nil, 'down')).code).to eq('provider_down')
      expect(described_class.from(Faraday::ConnectionFailed.new('refused')).code).to eq('provider_down')
    end

    it 'traduz timeout de rede em timeout' do
      expect(described_class.from(Faraday::TimeoutError.new('timeout')).code).to eq('timeout')
      expect(described_class.from(Net::ReadTimeout.new).code).to eq('timeout')
    end

    it 'cai em internal para erro desconhecido' do
      expect(described_class.from(StandardError.new('boom')).code).to eq('internal')
    end

    # Regressao verificada com emissor falso: no streaming o RubyLLM rebaixa o
    # 401 do provedor para BadRequestError. O agente nao pode ler "requisicao
    # invalida" quando o problema e a chave.
    it 'reconhece chave revogada mesmo quando o RubyLLM rebaixa o 401 para BadRequestError' do
      error = RubyLLM::BadRequestError.new(
        nil, 'Incorrect API key provided: sk-proj-FAKEKEY1234567890. You can find your API key at https://platform.openai.com.'
      )

      expect(described_class.from(error).code).to eq('unauthorized')
    end

    it 'reconhece cota estourada e rate limit rebaixados para BadRequestError' do
      expect(described_class.from(RubyLLM::BadRequestError.new(nil, 'You exceeded your current quota')).code).to eq('payment_required')
      expect(described_class.from(RubyLLM::BadRequestError.new(nil, 'Rate limit reached for gpt-4.1-mini')).code).to eq('rate_limited')
    end

    it 'mantem bad_request quando o provedor reclama do payload' do
      error = RubyLLM::BadRequestError.new(nil, "Invalid value for 'temperature': must be <= 2")

      expect(described_class.from(error).code).to eq('bad_request')
    end
  end

  describe '#to_event' do
    it 'nao carrega o corpo cru do provedor nem a credencial' do
      raw = 'Incorrect API key provided: sk-proj-abcdef123456. You can find your API key at ...'
      event = described_class.from(RubyLLM::UnauthorizedError.new(nil, raw)).to_event

      expect(event[:code]).to eq('unauthorized')
      expect(event[:message]).to eq(described_class::MESSAGES['unauthorized'])
      expect(event.to_json).not_to include('sk-proj')
      expect(event.to_json).not_to include('Incorrect API key')
    end
  end

  describe '#log_context' do
    it 'mantem contexto para depurar mas mascara a credencial' do
      raw = "Incorrect API key provided: sk-proj-abcdef123456\nnext line"
      context = described_class.from(RubyLLM::UnauthorizedError.new(nil, raw)).log_context

      expect(context).to include('error_code=unauthorized')
      expect(context).to include('error_class=RubyLLM::UnauthorizedError')
      expect(context).to include('[REDACTED]')
      expect(context).not_to include('sk-proj-abcdef123456')
    end

    it 'mascara tambem a chave que o provedor ja devolveu meio mascarada' do
      error = RubyLLM::BadRequestError.new(nil, 'Incorrect API key provided: sk-proj-**********************-401.')

      expect(described_class.from(error).log_context).to include('[REDACTED]')
      expect(described_class.from(error).log_context).not_to include('sk-proj-*')
    end

    it 'trunca mensagem gigante do provedor' do
      context = described_class.from(StandardError.new('a' * 1000)).log_context

      expect(context.length).to be < 500
      expect(context).to include('...')
    end
  end
end
