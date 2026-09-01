# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Waha::SessionStatusCache do
  let(:sessions_url) { 'https://waha.example.com/api/sessions?all=true' }
  let(:body) do
    [
      { 'name' => 'Simplex', 'status' => 'WORKING' },
      { 'name' => 'simplexteste', 'status' => 'FAILED' },
      { 'name' => 'parada', 'status' => 'STOPPED' }
    ].to_json
  end

  before do
    stub_const('ENV', ENV.to_h.merge('WAHA_API_URL' => 'https://waha.example.com', 'WAHA_API_KEY' => 'k'))
    described_class.reset!
  end

  after { described_class.reset! }

  describe '.working_sessions' do
    it 'devolve so as sessoes WORKING' do
      stub_request(:get, sessions_url).to_return(status: 200, body: body)

      expect(described_class.working_sessions).to eq(['Simplex'])
    end

    it 'cacheia: a segunda consulta nao bate na WAHA de novo' do
      stub_request(:get, sessions_url).to_return(status: 200, body: body)

      3.times { described_class.working_sessions }

      expect(a_request(:get, sessions_url)).to have_been_made.once
    end

    it 'devolve nil (desconhecido) quando a WAHA nao responde' do
      stub_request(:get, sessions_url).to_return(status: 500, body: 'boom')

      expect(described_class.working_sessions).to be_nil
    end

    # Sem isto, uma rajada de jobs com a WAHA fora repetiria a consulta por job —
    # trocariamos um timeout por LID por uma chamada por LID.
    it 'nao repete a consulta em rajada quando o status e desconhecido' do
      stub_request(:get, sessions_url).to_return(status: 500, body: 'boom')

      3.times { described_class.working_sessions }

      expect(a_request(:get, sessions_url)).to have_been_made.once
    end
  end

  describe '.usable?' do
    before { stub_request(:get, sessions_url).to_return(status: 200, body: body) }

    it 'e true para sessao WORKING' do
      expect(described_class).to be_usable('Simplex')
    end

    it 'e false para sessao FAILED (a que gerou os 2.812 timeouts da issue 27)' do
      expect(described_class).not_to be_usable('simplexteste')
    end

    it 'e false para sessao STOPPED' do
      expect(described_class).not_to be_usable('parada')
    end

    it 'e false para sessao que nem existe mais na WAHA' do
      expect(described_class).not_to be_usable('spx')
    end

    it 'e false para nome em branco' do
      expect(described_class).not_to be_usable(nil)
      expect(described_class).not_to be_usable('')
    end
  end

  describe 'fail-open' do
    it 'e usable? quando nao da para saber o status na WAHA' do
      stub_request(:get, sessions_url).to_return(status: 500, body: 'boom')

      expect(described_class).to be_usable('qualquer')
    end

    it 'e usable? quando o Redis esta fora' do
      stub_request(:get, sessions_url).to_return(status: 200, body: body)
      allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError, 'down')
      allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError, 'down')

      # Sem Redis nao ha cache, mas a consulta direta ainda decide corretamente.
      expect(described_class).to be_usable('Simplex')
      expect(described_class).not_to be_usable('simplexteste')
    end

    it 'nao levanta quando a resposta da WAHA vem num formato inesperado' do
      stub_request(:get, sessions_url).to_return(status: 200, body: { 'unexpected' => true }.to_json)

      expect { described_class.working_sessions }.not_to raise_error
    end
  end

  describe '.reset!' do
    it 'forca uma releitura na proxima consulta' do
      stub_request(:get, sessions_url).to_return(status: 200, body: body)
      described_class.working_sessions

      described_class.reset!
      described_class.working_sessions

      expect(a_request(:get, sessions_url)).to have_been_made.twice
    end
  end
end
