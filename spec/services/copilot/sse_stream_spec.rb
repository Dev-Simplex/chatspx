require 'rails_helper'

RSpec.describe Copilot::SseStream do
  let(:io) { StringIO.new }
  let(:sse) { described_class.new(io, heartbeat_interval: nil) }

  describe '#emit' do
    it 'escreve no formato SSE com id incremental' do
      sse.emit('token', delta: 'oi')
      sse.emit('done', message_id: 7, finish_reason: 'stop')

      expect(io.string).to eq(
        "id: 1\nevent: token\ndata: {\"delta\":\"oi\"}\n\n" \
        "id: 2\nevent: done\ndata: {\"message_id\":7,\"finish_reason\":\"stop\"}\n\n"
      )
    end

    it 'mantem o JSON em uma unica linha mesmo com quebra de linha no delta' do
      sse.emit('token', delta: "linha 1\nlinha 2")

      data_lines = io.string.lines.select { |line| line.start_with?('data:') }
      expect(data_lines.length).to eq(1)
      expect(JSON.parse(data_lines.first.delete_prefix('data: '))['delta']).to eq("linha 1\nlinha 2")
    end
  end

  describe '#keep_alive' do
    it 'escreve comentario que nao vira evento para o cliente' do
      sse.keep_alive

      expect(io.string).to eq(": keep-alive\n\n")
      expect(sse.sequence).to eq(0)
    end
  end

  describe 'cliente desconectado' do
    let(:broken_io) { instance_double(StringIO) }
    let(:sse) { described_class.new(broken_io, heartbeat_interval: nil) }

    before do
      allow(broken_io).to receive(:write).and_raise(IOError.new('closed stream'))
    end

    it 'levanta Disconnected e marca a conexao como morta' do
      expect { sse.emit('token', delta: 'oi') }.to raise_error(described_class::Disconnected)
      expect(sse.connected?).to be(false)
    end

    it 'nao tenta escrever de novo depois de desconectar' do
      expect { sse.emit('token', delta: 'oi') }.to raise_error(described_class::Disconnected)
      expect { sse.emit('token', delta: 'oi') }.to raise_error(described_class::Disconnected)

      expect(broken_io).to have_received(:write).once
    end
  end

  describe '#start_heartbeat!' do
    it 'emite keep-alive periodico enquanto a geracao roda' do
      stream = described_class.new(io, heartbeat_interval: 0.05)
      stream.start_heartbeat!
      sleep 0.2
      stream.stop_heartbeat!

      expect(io.string).to include(': keep-alive')
    end
  end
end
