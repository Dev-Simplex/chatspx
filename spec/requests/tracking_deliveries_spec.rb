require 'rails_helper'

# Bloco 5.14 — o log de entregas de rastreio por inbox, que e o que o painel de diagnostico le.
#
# POR QUE ESTE ARQUIVO EXISTE: as duas rotas que ele exercita foram chamadas pelo front por
# semanas contra um roteador que nao as tinha. Nenhum spec pegou, porque o spec do front dubla
# o axios e nunca toca a rota, e nao havia spec de backend nenhum — nao havia backend. So
# apareceu em navegador real, como 404.
RSpec.describe 'tracking_deliveries: log de rastreio da inbox', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  # Um evento com entrega FALHADA, que e o caso que o painel existe para mostrar.
  let(:event) do
    TrackingEvent.create!(name: 'chatspx_lead', account: account, inbox: inbox, dedup_key: 'fato-1',
                          properties: { 'valor' => 'R$ 1.234', 'origem' => 'google' })
  end
  let!(:falhada) do
    TrackingDelivery.create!(tracking_event: event, destination: :meta_capi, status: :failed,
                             http_status: 400, error_code: 'invalid_hash',
                             error_message: 'em is not a valid hash', attempts: 3,
                             emq: 6.5, field_names: %w[em ph event_name])
  end

  describe 'GET index' do
    it 'devolve a entrega falhada, com o motivo' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      linha = response.parsed_body['deliveries'].first
      expect(linha['status']).to eq('failed')
      expect(linha['http_status']).to eq(400)
      expect(linha['error_code']).to eq(falhada.error_code)
      expect(linha['error_message']).to eq(falhada.error_message)
      expect(linha['name']).to eq('chatspx_lead')
      expect(linha['attempts']).to eq(3)
    end

    # O envelope errado nao daria erro: daria lista vazia e silenciosa, e o painel diria
    # "nao saiu evento" com o banco cheio. Por isso a forma da RAIZ e assertada.
    it 'responde na RAIZ, sem envelope `payload` — que e como o front le' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).not_to have_key('payload')
      expect(response.parsed_body['deliveries']).to be_an(Array)
      expect(response.parsed_body['retention_days']).to eq(90)
      expect(response.parsed_body).to have_key('kill_switch')
    end

    # `emq` e `decimal(3,1)`: cru vira a STRING "6.5" no JSON, o painel filtra por
    # `typeof === 'number'` e a media aparece vazia com o banco cheio.
    it 'devolve `emq` como NUMERO, nao como string' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['deliveries'].first['emq']).to eq(6.5)
      expect(response.parsed_body['deliveries'].first['emq']).to be_a(Numeric)
    end

    it 'nao mistura entrega de OUTRA inbox da mesma conta' do
      outra = create(:inbox, account: account)
      outro_evento = TrackingEvent.create!(name: 'chatspx_lead', account: account, inbox: outra,
                                           dedup_key: 'fato-de-outra')
      TrackingDelivery.create!(tracking_event: outro_evento, destination: :ga4_mp, status: :sent)

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['deliveries'].size).to eq(1)
      expect(response.parsed_body['deliveries'].first['destination']).to eq('meta_capi')
    end

    it 'respeita o `limit` e nao aceita um teto absurdo pela URL' do
      12.times do |i|
        e = TrackingEvent.create!(name: 'chatspx_lead', account: account, inbox: inbox, dedup_key: "muitos-#{i}")
        TrackingDelivery.create!(tracking_event: e, destination: :ga4_mp, status: :sent)
      end

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries?limit=5",
          headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['deliveries'].size).to eq(5)

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries?limit=100000",
          headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['deliveries'].size).to eq(13)
    end

    it 'agente comum nao ve o log de rastreio' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'kill_switch reflete o que esta gravado na inbox' do
      inbox.update!(additional_attributes: { 'tracking_kill_switch' => true })

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['kill_switch']).to be(true)
    end
  end

  # O ACEITE do bloco, e ele so vale com dado de entrada que TENHA segredo: rodar esta busca
  # com o cofre vazio mediria zero e passaria sozinha.
  describe 'o segredo NUNCA aparece no log' do
    let!(:credencial) do
      create(:tracking_credential, account: account, inbox: inbox,
                                   meta_access_token: 'EAAsegredo-que-nao-pode-vazar-0001',
                                   ga4_api_secret: 'ga4-segredo-que-nao-pode-vazar-0002')
    end

    it 'o dado de entrada TEM segredo — senao esta busca mede zero' do
      expect(credencial.reload.meta_access_token).to eq('EAAsegredo-que-nao-pode-vazar-0001')
      expect(credencial.ga4_api_secret).to be_present
    end

    it 'nenhum segredo do cofre sai na resposta' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries",
          headers: admin.create_new_auth_token, as: :json

      expect(response.body).not_to include('EAAsegredo-que-nao-pode-vazar-0001')
      expect(response.body).not_to include('ga4-segredo-que-nao-pode-vazar-0002')
    end

    # `field_names` sao NOMES por validacao do modelo; o que carrega VALOR e `properties`,
    # e a lista fechada do jbuilder e o que o mantem de fora.
    it 'devolve os NOMES dos campos e nenhum valor do evento' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries",
          headers: admin.create_new_auth_token, as: :json

      linha = response.parsed_body['deliveries'].first
      expect(linha['field_names']).to eq(%w[em ph event_name])
      expect(linha).not_to have_key('properties')
      expect(response.body).not_to include('R$ 1.234')
    end
  end

  describe 'POST test — o disparo de evento de teste' do
    it 'registra o evento pelo caminho de verdade e devolve a entrega' do
      inbox.update!(additional_attributes: { 'widget_tracking' => { 'meta_pixel_id' => '123456' } })
      create(:tracking_credential, account: account, inbox: inbox,
                                   meta_access_token: 'EAAtoken-de-teste-0003')

      expect do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries/test",
             headers: admin.create_new_auth_token, as: :json
      end.to change { TrackingEvent.where(name: 'chatspx_diagnostic_test').count }.by(1)

      expect(response).to have_http_status(:success)
      entrega = response.parsed_body['delivery']
      expect(entrega['name']).to eq('chatspx_diagnostic_test')
      expect(entrega['destination']).to eq('meta_capi')
      expect(entrega['event_id']).to be_present
    end

    # Sem destino, "nao havia para onde tentar" e uma resposta diferente de "falhou".
    it 'sem credencial devolve `skipped` com o motivo, nao um erro' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries/test",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['delivery']['status']).to eq('skipped')
      expect(response.parsed_body['delivery']['error_code']).to eq('no_destination_configured')
    end

    # A dedup deriva de `occurred_at.to_i`: sem chave propria, dois cliques no mesmo segundo
    # devolveriam a MESMA entrega e o segundo teste nao teria disparado nada.
    it 'dois testes seguidos no mesmo segundo produzem DOIS eventos' do
      2.times do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries/test",
             headers: admin.create_new_auth_token, as: :json
      end

      expect(TrackingEvent.where(name: 'chatspx_diagnostic_test').count).to eq(2)
    end

    it 'agente comum nao dispara evento de teste' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_deliveries/test",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
