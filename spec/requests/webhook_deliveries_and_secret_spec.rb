require 'rails_helper'

# Bloco 4.14 — log de entregas, replay, rotacao e o segredo fora do index.
RSpec.describe 'webhooks: entregas, replay e segredo', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:webhook) do
    create(:webhook, account: account, url: 'https://destino.exemplo.com/h',
                     subscriptions: ['conversation_created'])
  end

  describe 'o segredo no index' do
    # A armadilha desta execucao: o upstream filtrou um campo na leitura enquanto o
    # formulario reenviava o objeto inteiro, e abrir "Editar" apagava a credencial do
    # cliente. Aqui os DOIS sentidos sao medidos.
    it 'NAO devolve o segredo em texto claro' do
      get "/api/v1/accounts/#{account.id}/webhooks", headers: admin.create_new_auth_token, as: :json

      corpo = response.parsed_body['payload']['webhooks'].first
      expect(corpo).not_to have_key('secret')
      expect(response.body).not_to include(webhook.secret)
    end

    it 'diz que EXISTE um segredo, sem dizer qual' do
      get "/api/v1/accounts/#{account.id}/webhooks", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['webhooks'].first['has_secret']).to be(true)
    end

    # O outro sentido: editar sem receber o segredo de volta nao pode apaga-lo.
    it 'editar o webhook NAO apaga o segredo' do
      antes = webhook.secret

      patch "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
            params: { webhook: { name: 'Outro nome', url: webhook.url, subscriptions: ['conversation_created'] } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(webhook.reload.secret).to eq(antes)
      expect(webhook.secret).to be_present
    end

    # E o caminho explicito: mesmo mandando secret: nil de proposito, nao passa.
    it 'nao aceita gravar secret pela API, nem nil nem valor' do
      antes = webhook.secret

      patch "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
            params: { webhook: { secret: nil, url: webhook.url, subscriptions: ['conversation_created'] } },
            headers: admin.create_new_auth_token, as: :json
      expect(webhook.reload.secret).to eq(antes)

      patch "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
            params: { webhook: { secret: 'forjado', url: webhook.url, subscriptions: ['conversation_created'] } },
            headers: admin.create_new_auth_token, as: :json
      expect(webhook.reload.secret).to eq(antes)
    end

    it 'a criacao devolve o segredo uma vez, que e quando da para copiar' do
      post "/api/v1/accounts/#{account.id}/webhooks",
           params: { webhook: { url: 'https://novo.exemplo.com/h', subscriptions: ['conversation_created'] } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['webhook']['secret']).to be_present
    end
  end

  describe 'rotacao' do
    it 'troca o segredo e devolve o novo uma vez' do
      antigo = webhook.secret

      post "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}/rotate_secret",
           headers: admin.create_new_auth_token, as: :json

      novo = response.parsed_body['payload']['webhook']['secret']
      expect(novo).to be_present
      expect(novo).not_to eq(antigo)
      expect(webhook.reload.secret).to eq(novo)
    end
  end

  describe 'log de entregas e replay' do
    let!(:falhada) do
      create(:webhook_delivery, webhook: webhook, account: account, status: :failed,
                                delivery_id: 'entrega-42', event: 'conversation_created',
                                http_status: 500, error_message: '500 Internal Server Error',
                                payload: { 'event' => 'conversation_created', 'id' => 7 })
    end

    it 'a tela mostra a entrega falhada, com o motivo' do
      get "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}/deliveries",
          headers: admin.create_new_auth_token, as: :json

      linha = response.parsed_body['payload']['deliveries'].first
      expect(linha['status']).to eq('failed')
      expect(linha['http_status']).to eq(500)
      expect(linha['error_message']).to eq('500 Internal Server Error')
      expect(linha['delivery_id']).to eq('entrega-42')
    end

    # O ponto do replay: o destino so consegue deduplicar se o id for o MESMO.
    it 'o reenvio chega com o MESMO X-Chatwoot-Delivery' do
      capturado = nil
      allow(WebhookJob).to receive(:perform_later) { |*args| capturado = args }

      post "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}/replay",
           params: { delivery_id: falhada.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(capturado[3][:delivery_id]).to eq('entrega-42')
      expect(response.parsed_body['delivery_id']).to eq('entrega-42')
    end

    it 'o reenvio conta a tentativa em vez de criar outra entrega' do
      allow(WebhookJob).to receive(:perform_later)

      expect do
        post "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}/replay",
             params: { delivery_id: falhada.id }, headers: admin.create_new_auth_token, as: :json
      end.to change { falhada.reload.attempts }.from(1).to(2)
                                               .and(not_change { WebhookDelivery.count })
    end
  end

  describe 'retencao de 7 dias' do
    it 'apaga o que passou de 7 dias e mantem o resto' do
      velha = create(:webhook_delivery, webhook: webhook, account: account, delivery_id: 'velha')
      nova = create(:webhook_delivery, webhook: webhook, account: account, delivery_id: 'nova')
      velha.update_columns(created_at: 8.days.ago) # rubocop:disable Rails/SkipsModelValidations

      Webhooks::DeliveryCleanupJob.perform_now

      expect(WebhookDelivery.exists?(velha.id)).to be(false)
      expect(WebhookDelivery.exists?(nova.id)).to be(true)
    end
  end

  describe 'ping de validacao no cadastro' do
    # Sem ping, a primeira entrega real e que descobre que a URL esta errada — e ela leva
    # junto um evento de cliente.
    it 'dispara um ping pelo mesmo caminho de uma entrega real' do
      capturado = nil
      allow(WebhookJob).to receive(:perform_later) { |*args| capturado = args }

      post "/api/v1/accounts/#{account.id}/webhooks",
           params: { webhook: { url: 'https://novo.exemplo.com/h', subscriptions: ['conversation_created'] } },
           headers: admin.create_new_auth_token, as: :json

      criado = Webhook.find(response.parsed_body['payload']['webhook']['id'])
      url, payload, tipo, kwargs = capturado
      expect(url).to eq('https://novo.exemplo.com/h')
      expect(tipo).to eq(:account_webhook)
      expect(payload[:event]).to eq('webhook.ping')
      expect(kwargs[:secret]).to eq(criado.secret)
      expect(kwargs[:webhook_id]).to eq(criado.id)
      expect(kwargs[:delivery_id]).to be_present
    end
  end
end
