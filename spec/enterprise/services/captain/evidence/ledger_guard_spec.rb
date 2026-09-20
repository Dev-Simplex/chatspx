require 'rails_helper'

# decision/check assert nonempty claims AND all decisions; these examples deliberately use those shared assertions.
# rubocop:disable RSpec/NoExpectationExample, RSpec/SpecFilePathFormat

RSpec.describe Captain::Evidence::FactGuard do
  let(:account) { create(:account, custom_attributes: { 'captain_fact_guard_shadow' => true }) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:incoming) { create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'Imóvel 9412') }
  let(:scope) do
    incoming
    Captain::Evidence::Scope.new(conversation: conversation, assistant: assistant)
  end
  let(:ledger) { Captain::Evidence::Ledger.new(scope) }
  let(:guard) { described_class.new(ledger) }
  let(:extractor) { Captain::Evidence::ClaimExtractor.new(scope) }

  around do |example|
    Captain::Evidence::Context.set(scope: scope, publication_path: 'test') { example.run }
  end

  def vista(rows, total: rows.size, code: 200, bound: true)
    data = rows.index_by { |row| row.fetch('Codigo') }.merge('total' => total)
    response = instance_double(HTTParty::Response, code: code, body: data.to_json, parsed_response: data)
    Captain::Evidence::Sources.vista(response, filter: {}, account_bound: bound, source_version: 'fixture-v1')
  end

  def property(id = '9412', **attributes)
    { 'Codigo' => id, 'ValorLocacao' => '3200.00', 'ValorCondominio' => '500.00', 'Condominio' => 'Nao', **attributes.stringify_keys }
  end

  def check(text)
    claims = extractor.extract(text)
    expect(claims).not_to be_empty
    guard.evaluate(claims)
  end

  def decision(text, expected)
    expect(check(text).map { |row| row[:decision] }).to all(eq(expected))
  end

  it 'conv 41803 reconstructed: blocks rent in text without link or query, and against current rent' do
    decision('O imóvel 9412 tem aluguel de R$ 2.400.', 'would_block')
    vista([property])
    decision('O imóvel 9412 tem aluguel de R$ 2.400.', 'would_block')
  end

  it 'blocks A price attributed to B even when every number occurs in the ledger' do
    vista([property('1001', ValorLocacao: '2400'), property('1002')])
    decision('Imóvel 1002: aluguel R$ 2.400', 'would_block')
  end

  it 'conv 36940 reconstructed: a positive condo fee does not prove gated community' do
    vista([property])
    decision('O imóvel 9412 fica em condomínio fechado.', 'would_block')
    decision('O imóvel 9412 é avulso.', 'would_allow')
  end

  it 'rejects all and none for a partial query but permits a proven complete count' do
    vista([property], total: 20)
    decision('Estas são todas as opções.', 'would_block')
    decision('Não há imóveis.', 'would_block')
    decision('Nenhum.', 'would_block')
    decision('Todos.', 'would_block')
    vista([], total: 0)
    decision('Não há imóveis.', 'would_allow')
  end

  it 'allows a legitimate query, monetary formatting, explicit entity and field aliases' do
    vista([property('9412', ImoCodigo: '009412')])
    decision('Imóvel 9412: aluguel R$ 3.200,00', 'would_allow')
    claim = Captain::Evidence::Sources.fact('property', '009412', 'ValorLocacao', 'money', '3200.00', 'BRL/month')
    expect(guard.evaluate([claim]).first[:decision]).to eq('would_allow')
  end

  it 'derives rent plus condo exactly with both operands and refuses a missing operand' do
    vista([property])
    verdict = check('Imóvel 9412: aluguel + condomínio R$ 3.700,00').first
    expect(verdict).to include(decision: 'would_allow', reason: 'derived_sum')
    expect(verdict[:evidence_ids].size).to eq(2)
    vista([property('1002', ValorCondominio: nil)])
    decision('Imóvel 1002: total R$ 3.700', 'would_block')
  end

  it 'allows only explicit deterministic rounding, never two percent price tolerance' do
    vista([property('9412', ValorLocacao: '3200.49')])
    claim = Captain::Evidence::Sources.fact('property', '9412', 'rent', 'money', '3200', 'BRL/month')
    expect(guard.evaluate([claim]).first[:decision]).to eq('would_block')
    expect(guard.evaluate([claim.merge(rounding: { digits: 0, mode: 'half_up' })]).first[:decision]).to eq('would_allow')
    decision('Imóvel 9412: aluguel R$ 3.250', 'would_block')
  end

  [500, 200].each do |status|
    it "does not authorize a fact from HTTP #{status} with an empty body" do
      response = instance_double(HTTParty::Response, code: status, body: '', parsed_response: {})
      Captain::Evidence::Sources.vista(response, filter: {}, account_bound: true, source_version: 'v1')
      decision('Imóvel 9412: aluguel R$ 3.200', 'would_block')
    end
  end

  it 'does not authorize a nonempty failed tool, global credentials, or unrelated FAQ/TTS/memory' do
    vista([property], code: 500)
    vista([property], bound: false)
    %w[tts memory faq custom_http unit_record assistant_record].each do |origin|
      ledger.record(origin: origin, name: origin, version: '1', status: 'success', result: property,
                    facts: Captain::Evidence::Sources.property_facts(property))
    end
    decision('Imóvel 9412: aluguel R$ 3.200', 'would_block')
  end

  it 'stores the complete result beyond both previews and authorizes a fact at the end' do
    data = property.merge('Description' => 'x' * 12_000)
    vista([data])
    expect(Captain::EvidenceSource.last.full_result['data']['9412']['Description'].length).to eq(12_000)
    decision('Imóvel 9412: aluguel R$ 3.200', 'would_allow')
  end

  it 'enforces composite tenant and episode identity in the database' do
    vista([property])
    source = Captain::EvidenceSource.last
    expect do
      Captain::EvidenceSource.transaction(requires_new: true) { source.update!(episode_key: 'other') }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(source.reload.episode_key).to eq(scope.episode_key)
  end

  it 'never reads facts from another tenant or episode' do
    vista([property])
    foreign_scope = scope.dup
    foreign_scope.instance_variable_set(:@account_id, account.id + 1)
    expect(Captain::Evidence::Ledger.new(foreign_scope).snapshot).to be_empty
    foreign_scope.instance_variable_set(:@account_id, account.id)
    foreign_scope.instance_variable_set(:@episode_key, 'another-episode')
    expect(Captain::Evidence::Ledger.new(foreign_scope).snapshot).to be_empty
  end

  it 'excludes expired sources and sources from a different run by default' do
    vista([property])
    Captain::EvidenceSource.last.update!(expires_at: 1.second.ago)
    decision('Imóvel 9412: aluguel R$ 3.200', 'would_block')
    vista([property])
    Captain::EvidenceSource.last.update!(run_id: SecureRandom.uuid)
    decision('Imóvel 9412: aluguel R$ 3.200', 'would_block')
  end

  it 'simulates blocking when the ledger cannot be read' do
    allow(ledger).to receive(:snapshot).and_raise(Captain::Evidence::Ledger::Unavailable)
    expect(check('Imóvel 9412: aluguel R$ 3.200').first).to include(decision: 'would_block', reason: 'ledger_unavailable')
  end

  it 'permits formatted phone and negative coordinate from the account unit' do
    unit = Unit.create!(account: account, name: 'Central', timezone: 'America/Cuiaba',
                        phone: '5566999991234', latitude: '-11.852', longitude: '-55.500', address: 'Rua Teste, 1')
    Captain::Evidence::Sources.unit(unit)
    decision('Telefone: +55 (66) 99999-1234', 'would_allow')
    decision('Latitude: -11.852; longitude: -55.500', 'would_allow')
    decision('Latitude: 11.852', 'would_block')
    fact = Captain::Evidence::Sources.fact('unit', unit.id, 'address', 'text', unit.address, 'text')
    expect(guard.evaluate([fact]).first[:decision]).to eq('would_allow')
  end

  it 'quotes user and ad amounts without promoting either to current catalog prices' do
    incoming.update!(content: 'Meu orçamento é R$ 2.400', content_attributes: { referral: { body: 'Aluguel R$ 2.500' } })
    Captain::Evidence::Sources.quotes(incoming)
    decision('Você informou R$ 2.400.', 'would_allow')
    decision('O anúncio dizia R$ 2.500.', 'would_allow')
    decision('Imóvel 9412: aluguel R$ 2.400', 'would_block')
    decision('Imóvel 9412: aluguel R$ 2.500', 'would_block')
  end

  it 'does not treat list or card renderer indices as commercial claims' do
    vista([property])
    decision('1. Imóvel 9412: aluguel R$ 3.200', 'would_allow')
    payload = { 'card_index' => 500, 'body' => { 'text' => 'Imóvel 9412: aluguel R$ 3.200' } }
    text = Captain::Evidence::Shadow.visible_text(payload).join("\n")
    expect(text).not_to include('500')
    decision(text, 'would_allow')
    expect(extractor.extract('1. Olá')).to be_empty
  end

  it 'records shadow violations but still persists the outgoing message, including tool paths' do
    Captain::Evidence::Context.with_path('tool:responder_em_audio_tool') do
      message = create(:message, conversation: conversation, account: account, message_type: :outgoing,
                                 content: 'Imóvel 9412: aluguel R$ 2.400')
      expect(message).to be_persisted
      expect(Captain::FactGuardEvent.where(publication_path: 'tool:responder_em_audio_tool', decision: 'would_block')).to exist
    end
  end

  it 'keeps publishing in shadow if the event table fails and emits independent outage telemetry' do
    allow(Captain::FactGuardEvent).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid)
    allow(Captain::Evidence::Telemetry).to receive(:emit).and_call_original
    message = create(:message, conversation: conversation, account: account, message_type: :outgoing,
                               content: 'Imóvel 9412: aluguel R$ 2.400')
    expect(message).to be_persisted
    expect(Captain::Evidence::Telemetry).to have_received(:emit).with(hash_including(reason: 'ledger_unavailable'))
  end
end
# rubocop:enable RSpec/NoExpectationExample, RSpec/SpecFilePathFormat
