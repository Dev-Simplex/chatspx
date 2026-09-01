# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conversation WAHA group API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:group_jid) { '556696571379-1634750731@g.us' }
  let(:contact) { create(:contact, account: account, identifier: group_jid) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/waha_group" }
  let(:v2_url) { "https://waha.example.com/api/Simplex/groups/#{group_jid}/participants/v2" }

  before do
    stub_const('ENV', ENV.to_h.merge('WAHA_API_URL' => 'https://waha.example.com', 'WAHA_API_KEY' => 'k'))
    inbox.update!(waha_session_name: 'Simplex')
    create(:inbox_member, inbox: inbox, user: agent)
    Redis::Alfred.delete("waha:group_sync:forced:#{conversation.id}")
    Redis::Alfred.delete('waha:group_sync:circuit:Simplex')
    Redis::Alfred.delete(Waha::GroupLocator.group_session_key(group_jid))
  end

  describe 'GET .../waha_group' do
    it 'exige autenticação' do
      get url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'devolve never_synced quando a conversa nunca sincronizou' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['ok']).to be(true)
      expect(body['status']).to eq('never_synced')
      expect(body['waha_group']).to be_nil
    end

    it 'devolve o snapshot gravado sem chamar a WAHA' do
      stub = stub_request(:get, v2_url)
      snapshot = { 'participants' => [{ 'lid' => '229480102662169', 'phone' => '556699990001', 'name' => nil, 'admin' => true }],
                   'count' => 1, 'synced_at' => Time.current.utc.iso8601 }
      conversation.update!(additional_attributes: { 'waha_group' => snapshot })

      get url, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['waha_group']).to eq(snapshot)
      expect(stub).not_to have_been_requested
    end
  end

  describe 'POST .../waha_group' do
    it 'sincroniza agora e devolve o snapshot' do
      stub_request(:get, v2_url).to_return(status: 200, body: file_fixture('waha/group_participants_v2.json').read)

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['ok']).to be(true)
      expect(body['status']).to eq('synced')
      expect(body['waha_group']['count']).to eq(3)
      expect(body['waha_group']['participants'].first['phone']).to eq('556699990001')
    end

    it 'não quebra a tela quando a WAHA está fora do ar' do
      stub_request(:get, v2_url).to_timeout
      stub_request(:get, "https://waha.example.com/api/Simplex/groups/#{group_jid}/participants").to_timeout

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('ok' => false, 'status' => 'failed', 'waha_group' => nil)
    ensure
      Redis::Alfred.delete('waha:group_sync:circuit:Simplex')
    end

    it 'responde not_a_group em conversa 1:1, sem tocar na conversa' do
      solo = create(:conversation, account: account, inbox: inbox)

      post "/api/v1/accounts/#{account.id}/conversations/#{solo.display_id}/waha_group",
           headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('ok' => false, 'reason' => 'not_a_group')
      expect(solo.reload.additional_attributes).not_to have_key('waha_group')
    end

    it 'nega o agente que não tem acesso à caixa' do
      outsider = create(:user, account: account, role: :agent)

      post url, headers: outsider.create_new_auth_token, as: :json

      # Pundit::NotAuthorizedError vira 401 neste repo (mesmo comportamento dos
      # demais sub-recursos de conversa).
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
