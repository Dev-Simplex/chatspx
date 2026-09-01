require 'rails_helper'

RSpec.describe Copilot::StreamCancellation do
  subject(:cancellation) { described_class.new(4242) }

  after { cancellation.clear! }

  it 'comeca sem pedido de cancelamento' do
    expect(cancellation.requested?).to be(false)
  end

  it 'enxerga o pedido feito por outro processo' do
    described_class.new(4242).request!

    expect(described_class.new(4242).requested?).to be(true)
  end

  it 'nao vaza cancelamento entre threads diferentes' do
    described_class.new(4242).request!

    expect(described_class.new(9999).requested?).to be(false)
  end

  it 'limpa o pedido' do
    cancellation.request!
    cancellation.clear!

    expect(described_class.new(4242).requested?).to be(false)
  end

  # Uma ida ao Redis por token seria uma chamada de rede por palavra digitada.
  it 'nao consulta o Redis a cada chunk' do
    allow(Redis::Alfred).to receive(:exists?).and_return(false)

    5.times { cancellation.requested? }

    expect(Redis::Alfred).to have_received(:exists?).once
  end

  it 'para de consultar depois que o cancelamento e confirmado' do
    allow(Redis::Alfred).to receive(:exists?).and_return(true)

    3.times { expect(cancellation.requested?).to be(true) }

    expect(Redis::Alfred).to have_received(:exists?).once
  end
end
