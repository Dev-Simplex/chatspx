# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Waha::GroupSyncService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:group_jid) { '556696571379-1634750731@g.us' }
  let(:contact) { create(:contact, account: account, identifier: group_jid, name: 'TI TOZI - Inovação (GROUP)') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:v2_url) { "https://waha.example.com/api/Simplex/groups/#{CGI.escape(group_jid).gsub('%40', '@')}/participants/v2" }
  let(:v1_url) { "https://waha.example.com/api/Simplex/groups/#{CGI.escape(group_jid).gsub('%40', '@')}/participants" }
  let(:v1_body) { file_fixture('waha/group_participants.json').read }
  let(:v2_body) { file_fixture('waha/group_participants_v2.json').read }

  before do
    stub_const('ENV', ENV.to_h.merge('WAHA_API_URL' => 'https://waha.example.com', 'WAHA_API_KEY' => 'k'))
    inbox.update!(waha_session_name: 'Simplex')
    Redis::Alfred.delete('waha:group_sync:circuit:Simplex')
    Redis::Alfred.delete("waha:group_sync:forced:#{conversation.id}")
    # O índice grupo -> sessão é global e sobrevive entre exemplos (é justamente
    # o ponto dele); zeramos para cada exemplo escolher a sessão de propósito.
    Redis::Alfred.delete(Waha::GroupLocator.group_session_key(group_jid))
  end

  describe '#perform' do
    it 'grava o snapshot no formato do contrato C3' do
      stub_request(:get, v2_url).to_return(status: 200, body: v2_body)

      result = described_class.new(conversation, force: true).perform

      expect(result).to be_ok
      expect(result.status).to eq('synced')

      snapshot = conversation.reload.additional_attributes['waha_group']
      expect(snapshot['count']).to eq(3)
      expect(snapshot['participants'].first).to eq(
        'lid' => '229480102662169', 'phone' => '556699990001', 'name' => nil, 'admin' => true
      )
      expect { Time.iso8601(snapshot['synced_at']) }.not_to raise_error
    end

    it 'prefere /participants/v2 e não chama a v1 quando ela responde' do
      stub_request(:get, v2_url).to_return(status: 200, body: v2_body)
      v1_stub = stub_request(:get, v1_url).to_return(status: 200, body: v1_body)

      described_class.new(conversation, force: true).perform

      expect(v1_stub).not_to have_been_requested
    end

    it 'cai para /participants quando a v2 não existe naquela versão da WAHA' do
      stub_request(:get, v2_url).to_return(status: 501, body: { message: 'not implemented' }.to_json)
      stub_request(:get, v1_url).to_return(status: 200, body: v1_body)

      result = described_class.new(conversation, force: true).perform

      expect(result.status).to eq('synced')
      expect(conversation.reload.additional_attributes.dig('waha_group', 'count')).to eq(3)
    end

    it 'alimenta o cache LID->PN e o índice grupo -> sessão com a mesma resposta' do
      stub_request(:get, v2_url).to_return(status: 200, body: v2_body)

      described_class.new(conversation, force: true).perform

      expect(Whatsapp::LidPhoneCache.read('Simplex', '229480102662169')).to eq('556699990001')
      expect(Waha::GroupLocator.indexed_session(group_jid)).to eq('Simplex')
    ensure
      Redis::Alfred.delete(Whatsapp::LidPhoneCache.key('Simplex', '229480102662169'))
      Redis::Alfred.delete(Waha::GroupLocator.group_session_key(group_jid))
    end

    it 'não toca em conversa que não é de grupo' do
      solo = create(:conversation, account: account, inbox: inbox)

      result = described_class.new(solo, force: true).perform

      expect(result).not_to be_ok
      expect(result.reason).to eq('not_a_group')
      expect(solo.reload.additional_attributes).not_to have_key('waha_group')
    end

    it 'não chama a WAHA quando o snapshot ainda está fresco' do
      stub = stub_request(:get, v2_url).to_return(status: 200, body: v2_body)
      conversation.update!(
        additional_attributes: { 'waha_group' => { 'participants' => [], 'count' => 0, 'synced_at' => 1.minute.ago.utc.iso8601 } }
      )

      result = described_class.new(conversation).perform

      expect(result.status).to eq('cached')
      expect(stub).not_to have_been_requested
    end

    it 'segura o botão Sincronizar agora dentro da janela mínima' do
      stub_request(:get, v2_url).to_return(status: 200, body: v2_body)
      described_class.new(conversation, force: true).perform

      result = described_class.new(conversation.reload, force: true).perform

      expect(result.status).to eq('throttled')
      expect(result.reason).to eq('force_throttled')
    end

    context 'when WAHA is down' do
      it 'não levanta, não escreve e devolve ok: false' do
        stub_request(:get, v2_url).to_timeout
        stub_request(:get, v1_url).to_timeout

        result = described_class.new(conversation, force: true).perform

        expect(result).not_to be_ok
        expect(result.status).to eq('failed')
        expect(result.reason).to eq('waha_unavailable')
        expect(conversation.reload.additional_attributes).not_to have_key('waha_group')
      end

      it 'preserva o snapshot anterior' do
        previous = { 'participants' => [{ 'lid' => '1', 'phone' => '2', 'name' => nil, 'admin' => false }],
                     'count' => 1, 'synced_at' => 2.hours.ago.utc.iso8601 }
        conversation.update!(additional_attributes: { 'waha_group' => previous })
        stub_request(:get, v2_url).to_timeout
        stub_request(:get, v1_url).to_timeout

        result = described_class.new(conversation, force: true).perform

        expect(result.snapshot).to eq(previous)
        expect(conversation.reload.additional_attributes['waha_group']).to eq(previous)
      end

      it 'abre o circuito da sessão e para de bater nela' do
        stub_request(:get, v2_url).to_timeout
        stub_request(:get, v1_url).to_timeout
        described_class.new(conversation, force: true).perform
        Redis::Alfred.delete("waha:group_sync:forced:#{conversation.id}")

        result = described_class.new(conversation, force: true).perform

        expect(result.reason).to eq('circuit_open')
      ensure
        Redis::Alfred.delete('waha:group_sync:circuit:Simplex')
      end

      it 'devolve erro quando a sessão não existe mais (422)' do
        stub_request(:get, v2_url).to_return(status: 422, body: { message: 'Session "Simplex" does not exist' }.to_json)
        stub_request(:get, v1_url).to_return(status: 422, body: { message: 'Session "Simplex" does not exist' }.to_json)

        result = described_class.new(conversation, force: true).perform

        expect(result.reason).to eq('waha_error')
        expect(conversation.reload.additional_attributes).not_to have_key('waha_group')
      end
    end

    it 'devolve no_session quando não há de onde tirar a sessão' do
      inbox.update!(waha_session_name: nil)

      result = described_class.new(conversation, force: true).perform

      expect(result.reason).to eq('no_session')
    end
  end

  describe '.store_snapshot' do
    let(:groups) { JSON.parse(file_fixture('waha/groups.json').read) }

    it 'grava a partir do payload de GET /groups, sem HTTP' do
      snapshot = described_class.store_snapshot(conversation, groups.first)

      expect(snapshot['count']).to eq(2)
      expect(conversation.reload.additional_attributes.dig('waha_group', 'participants').first['phone']).to eq('556699990001')
    end

    it 'não reescreve quando a lista de participantes não mudou' do
      described_class.store_snapshot(conversation, groups.first)

      expect(described_class.store_snapshot(conversation.reload, groups.first)).to be_nil
    end

    it 'preserva o resto de additional_attributes' do
      conversation.update!(additional_attributes: { 'browser' => { 'device_name' => 'x' } })

      described_class.store_snapshot(conversation, groups.first)

      expect(conversation.reload.additional_attributes['browser']).to eq('device_name' => 'x')
    end

    it 'ignora payload sem participante' do
      expect(described_class.store_snapshot(conversation, { 'JID' => group_jid, 'Participants' => [] })).to be_nil
    end
  end
end
