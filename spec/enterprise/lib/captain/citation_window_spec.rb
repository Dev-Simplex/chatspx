require 'rails_helper'

# 6.03 — a citação como DADO. Nada aqui lê texto de modelo.
RSpec.describe Captain::CitationWindow do
  after { described_class.close! }

  it 'is a no-op outside an open window, so nothing accumulates by accident' do
    described_class.record(title: 'Política', source: 'https://exemplo.com/x', excerpt: 'texto')

    expect(described_class.citations).to eq([])
    expect(described_class.open?).to be(false)
  end

  it 'records what the retrieval brought' do
    described_class.open!
    described_class.record(title: 'Política de trocas', source: 'https://exemplo.com/trocas', excerpt: '  30 dias  ')

    expect(described_class.citations).to eq(
      [{ 'title' => 'Política de trocas', 'url' => 'https://exemplo.com/trocas', 'excerpt' => '30 dias' }]
    )
  end

  # Documento interno não vira link: href quebrado com a marca do cliente em volta é
  # pior do que referência sem link.
  it 'only turns a real http(s) source into a URL' do
    described_class.open!
    described_class.record(title: 'Manual', source: 'PDF:manual.pdf', excerpt: 'x')
    described_class.record(title: 'Colado', source: 'TEXT:algum texto', excerpt: 'x')

    expect(described_class.citations.map { |c| c['url'] }).to eq([nil, nil])
    expect(described_class.citations.map { |c| c['title'] }).to eq(%w[Manual Colado])
  end

  it 'falls back to the URL when the document has no name' do
    described_class.open!
    described_class.record(title: nil, source: 'https://exemplo.com/trocas', excerpt: 'x')

    expect(described_class.citations.first['title']).to eq('https://exemplo.com/trocas')
  end

  it 'drops a citation that would have no name at all' do
    described_class.open!
    described_class.record(title: nil, source: 'PDF:sem-nome.pdf', excerpt: 'x')

    expect(described_class.citations).to be_empty
  end

  it 'does not repeat the same document twice' do
    described_class.open!
    2.times { described_class.record(title: 'Política', source: 'https://exemplo.com/x', excerpt: 'a') }

    expect(described_class.citations.size).to eq(1)
  end

  it 'stops at the declared ceiling' do
    described_class.open!
    (described_class::MAX_CITATIONS + 3).times do |i|
      described_class.record(title: "Doc #{i}", source: "https://exemplo.com/#{i}", excerpt: 'x')
    end

    expect(described_class.citations.size).to eq(described_class::MAX_CITATIONS)
  end

  it 'cuts the excerpt at the declared limit' do
    described_class.open!
    described_class.record(title: 'Longo', source: 'https://exemplo.com/l', excerpt: 'a' * 500)

    expect(described_class.citations.first['excerpt'].length).to eq(described_class::EXCERPT_LIMIT)
  end

  it 'is closed by close!, so nothing leaks into the next response on this thread' do
    described_class.open!
    described_class.record(title: 'Política', source: 'https://exemplo.com/x', excerpt: 'x')
    described_class.close!

    expect(described_class.open?).to be(false)
    expect(described_class.citations).to eq([])
  end
end
