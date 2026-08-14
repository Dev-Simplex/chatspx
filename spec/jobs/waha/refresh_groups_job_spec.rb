# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Waha::RefreshGroupsJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:group_jid) { '556696571379-1634750731@g.us' }
  let(:contact) { create(:contact, account: account, identifier: group_jid) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:sessions_url) { 'https://waha.example.com/api/sessions?all=true' }
  let(:groups_url) { 'https://waha.example.com/api/Simplex/groups' }
  let(:groups_body) { file_fixture('waha/groups.json').read }

  before do
    stub_const('ENV', ENV.to_h.merge('WAHA_API_URL' => 'https://waha.example.com', 'WAHA_API_KEY' => 'k'))
    inbox.update!(waha_session_name: 'Simplex')
    stub_request(:get, sessions_url).to_return(
      status: 200,
      body: [{ 'name' => 'Simplex', 'status' => 'WORKING' }, { 'name' => 'simplexteste', 'status' => 'FAILED' }].to_json
    )
  end

  after do
    Redis::Alfred.delete(Whatsapp::LidPhoneCache.key('Simplex', '229480102662169'))
    Redis::Alfred.delete(Whatsapp::LidPhoneCache.key('Simplex', '224515288227943'))
    Redis::Alfred.delete(Whatsapp::LidPhoneCache.key('Simplex', '101958815846617'))
    Redis::Alfred.delete(Waha::GroupLocator.group_session_key(group_jid))
    Redis::Alfred.delete(Waha::GroupLocator.group_session_key('120363287968160641@g.us'))
  end

  it 'popula o cache LID->PN em lote com a resposta que antes era descartada' do
    stub_request(:get, groups_url).to_return(status: 200, body: groups_body)

    described_class.perform_now

    expect(Whatsapp::LidPhoneCache.read('Simplex', '229480102662169')).to eq('556699990001')
    expect(Whatsapp::LidPhoneCache.read('Simplex', '101958815846617')).to eq('556699990004')
  end

  it 'indexa em qual sessão cada grupo vive' do
    stub_request(:get, groups_url).to_return(status: 200, body: groups_body)

    described_class.perform_now

    expect(Waha::GroupLocator.indexed_session(group_jid)).to eq('Simplex')
  end

  it 'grava o snapshot das conversas de grupo sem nenhuma chamada HTTP extra' do
    groups_stub = stub_request(:get, groups_url).to_return(status: 200, body: groups_body)

    described_class.perform_now

    expect(groups_stub).to have_been_requested.once
    snapshot = conversation.reload.additional_attributes['waha_group']
    expect(snapshot['count']).to eq(2)
    expect(snapshot['participants'].pluck('phone')).to eq(%w[556699990001 556699990002])
  end

  it 'não bate em sessão que não está WORKING' do
    other = create(:inbox, account: account, channel: create(:channel_api, account: account))
    other.update!(waha_session_name: 'simplexteste')
    stub_request(:get, groups_url).to_return(status: 200, body: groups_body)
    stale = stub_request(:get, 'https://waha.example.com/api/simplexteste/groups')

    described_class.perform_now

    expect(stale).not_to have_been_requested
  end

  it 'varre sessão WORKING mesmo quando nenhuma caixa a declara' do
    inbox.update!(waha_session_name: nil)
    groups_stub = stub_request(:get, groups_url).to_return(status: 200, body: groups_body)

    described_class.perform_now

    expect(groups_stub).to have_been_requested
  end

  it 'respeita WAHA_REFRESH_SESSIONS_DISCOVERY=false' do
    inbox.update!(waha_session_name: nil)
    stub_const('ENV', ENV.to_h.merge('WAHA_API_URL' => 'https://waha.example.com', 'WAHA_REFRESH_SESSIONS_DISCOVERY' => 'false'))
    groups_stub = stub_request(:get, groups_url).to_return(status: 200, body: groups_body)

    described_class.perform_now

    expect(groups_stub).not_to have_been_requested
  end

  it 'não levanta quando a WAHA devolve erro na sessão' do
    stub_request(:get, groups_url).to_return(status: 422, body: { message: 'Session "Simplex" does not exist' }.to_json)

    expect { described_class.perform_now }.not_to raise_error
    expect(conversation.reload.additional_attributes).not_to have_key('waha_group')
  end

  it 'não levanta quando a WAHA está fora do ar' do
    stub_request(:get, groups_url).to_timeout

    expect { described_class.perform_now }.not_to raise_error
  end

  it 'cai para as sessões declaradas quando não consegue listar as sessões' do
    stub_request(:get, sessions_url).to_timeout
    groups_stub = stub_request(:get, groups_url).to_return(status: 200, body: groups_body)

    described_class.perform_now

    expect(groups_stub).to have_been_requested
  end
end
