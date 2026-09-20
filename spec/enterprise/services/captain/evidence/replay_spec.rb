require 'rails_helper'

RSpec.describe 'Captain evidence HTTP replay' do # rubocop:disable RSpec/DescribeClass -- integration across tool, HTTP, ledger and publication observer
  let(:fixture) { JSON.parse(File.read(File.join(__dir__, 'fixtures/vista_rent.json'))) }
  let(:account) { create(:account, custom_attributes: { 'captain_fact_guard_shadow' => true }) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  it 'replays full HTTP bodies through the real query adapter and observes scripted model candidates' do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: fixture.fetch('incoming'))
    tool = Captain::Tools::BuscarImovelTool.new(assistant)
    allow(tool).to receive_messages(vista_api_key: 'test-key', vista_base_url: 'https://catalog.example.test',
                                    evidence_vista_provenance: { account_bound: true, source_version: 'replay-v1' })
    responses = fixture.fetch('http_responses').map { |row| { status: row.fetch('status'), body: row.fetch('body').to_json } }
    request = stub_request(:get, %r{\Ahttps://catalog.example.test/imoveis/listar\?}).with do |req|
      pesquisa = JSON.parse(req.uri.query_values.fetch('pesquisa'))
      pesquisa.fetch('filter') == fixture.fetch('tool_request').fetch('filter')
    end.to_return(*responses)

    Captain::Evidence::Shadow.with_run(conversation, assistant) do
      tool.send(:fetch_vista, fixture.fetch('tool_request').fetch('filter'))
      fixture.fetch('model_candidates').each do |candidate|
        result = Captain::Evidence::Shadow.observe(text: candidate.fetch('text'), stage: 'replay')
        assessed = result.reject { |row| row[:fact_type] == 'coverage' }
        expect(assessed).not_to be_empty
        expect(assessed.pluck(:decision)).to all(eq(candidate.fetch('expected')))
      end
    end
    expect(request).to have_been_requested.once
    expect(Captain::EvidenceSource.last.full_result['body']).to eq(responses.last[:body])
  end

  it 'keeps a timeout and failed retry from becoming a zero-result commercial fact' do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: fixture.fetch('incoming'))
    tool = Captain::Tools::BuscarImovelTool.new(assistant)
    allow(tool).to receive_messages(vista_api_key: 'test-key', vista_base_url: 'https://catalog.example.test')
    allow(tool).to receive(:sleep) # deterministic retry without wall-clock waiting
    request = stub_request(:get, %r{https://catalog.example.test/imoveis/listar}).to_timeout
    Captain::Evidence::Shadow.with_run(conversation, assistant) do
      expect { tool.send(:fetch_vista, { 'Codigo' => '9412' }) }.to raise_error(Net::OpenTimeout)
      result = Captain::Evidence::Shadow.observe(text: 'Imóvel 9412: aluguel R$ 3.200', stage: 'replay')
      expect(result).to include(hash_including(fact_type: 'rent', decision: 'would_block'))
    end
    expect(request).to have_been_requested.twice
  end

  it 'stores malformed HTTP bodies intact as errors rather than treating them as evidence' do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: fixture.fetch('incoming'))
    Captain::Evidence::Shadow.with_run(conversation, assistant) do
      response = instance_double(HTTParty::Response, code: 200, body: '{broken', parsed_response: '{broken')
      Captain::Evidence::Sources.vista(response, filter: {}, account_bound: true, source_version: 'replay-v1')
      expect(Captain::EvidenceSource.last).to have_attributes(status: 'error', full_result: hash_including('body' => '{broken'))
      expect(Captain::EvidenceFact.count).to eq(0)
    end
  end

  it 'has no observation or runtime behavior change when the tenant has not opted in' do
    account.update!(custom_attributes: {})
    expect do
      result = Captain::Evidence::Shadow.with_run(conversation, assistant) { :existing_result }
      expect(result).to eq(:existing_result)
    end.not_to change(Captain::FactGuardEvent, :count)
  end

  it 'captures a complete public tool return but rejects another tenants tool as a source' do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: fixture.fetch('incoming'))
    klass = Class.new(Captain::Tools::BasePublicTool) do
      def perform(_context, **_args)
        'x' * 2500
      end
    end
    stub_const('Captain::Tools::EvidenceFixtureTool', klass)
    other = create(:captain_assistant)
    Captain::Evidence::Shadow.with_run(conversation, assistant) do
      expect(klass.new(assistant).perform(nil).size).to eq(2500)
      expect(Captain::EvidenceSource.last.full_result.fetch('output').size).to eq(2500)
      expect { klass.new(other).perform(nil) }.not_to change(Captain::EvidenceSource, :count)
      expect(Captain::EvidenceFact.count).to eq(0)
    end
    expect(Captain::Evidence::Context.scope).to be_nil
  end
end
