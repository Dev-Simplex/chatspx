require 'rails_helper'

# Bloco 4.13 — rotacao do segredo de assinatura do agent bot e da inbox de canal API.
#
# As duas rotas ja existiam em `config/routes.rb` e a tela da inbox JA chamava a sua. O que
# faltava era o resto do caminho: a policy (sem ela `authorize` levanta
# Pundit::NotDefinedError), a acao no controller do agent bot, o `reset_secret!` no modelo
# e a view. Request spec de proposito: e o unico jeito de medir a rota, a policy, o
# controller, o modelo e o serializador de uma vez — dublar qualquer um deles esconderia
# justamente o elo que faltava.
RSpec.describe 'rotacao do segredo de assinatura', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'POST /api/v1/accounts/:account_id/agent_bots/:id/reset_secret' do
    let!(:agent_bot) { create(:agent_bot, account: account) }

    it 'troca o segredo e devolve o novo UMA vez' do
      anterior = agent_bot.secret

      post "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}/reset_secret",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(agent_bot.reload.secret).not_to eq(anterior)
      expect(response.parsed_body['secret']).to eq(agent_bot.secret)
    end

    # O valor so aparece na criacao e na rotacao. Uma listagem que devolve segredo entrega
    # a chave de todos os bots a qualquer tela, log de proxy ou aba aberta.
    it 'e o index NAO devolve segredo nenhum' do
      get "/api/v1/accounts/#{account.id}/agent_bots", headers: admin.create_new_auth_token, as: :json

      corpo = response.parsed_body.find { |bot| bot['id'] == agent_bot.id }
      expect(corpo).not_to have_key('secret')
      expect(corpo['has_secret']).to be(true)
      expect(response.body).not_to include(agent_bot.secret)
    end

    it 'agente comum nao rotaciona' do
      post "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}/reset_secret",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(agent_bot.reload.secret).to be_present
    end

    # Espelho captain nao dispara webhook nenhum (`process_webhook_bot_event` corta antes),
    # entao rotacionar o segredo dele nao teria o que assinar — e o bot e imutavel via API.
    it 'espelho captain e imutavel' do
      assistant = create(:captain_assistant, account: account)
      espelho = assistant.reload.agent_bot

      post "/api/v1/accounts/#{account.id}/agent_bots/#{espelho.id}/reset_secret",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/reset_secret' do
    let(:channel_api) { create(:channel_api, account: account) }
    let(:inbox) { channel_api.inbox }

    before { create(:inbox_member, user: admin, inbox: inbox) }

    it 'troca o segredo do canal e devolve a inbox com o novo' do
      anterior = channel_api.secret
      expect(anterior).to be_present

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/reset_secret",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(channel_api.reload.secret).not_to eq(anterior)
      expect(response.parsed_body['secret']).to eq(channel_api.secret)
    end

    # O segredo devolvido tem de ser o valor USAVEL, nao o envelope. Enquanto a classe nao
    # tinha o concern, este campo carregava o ciphertext `{"p":"..."}` e quem tentasse
    # conferir a assinatura com ele nunca fecharia a conta.
    it 'devolve o segredo em claro, e nao o envelope cifrado' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/reset_secret",
           headers: admin.create_new_auth_token, as: :json

      # A presenca vem primeiro: sem ela, uma resposta de erro (sem campo `secret`) tambem
      # "nao comeca com o envelope" e o exemplo passaria medindo nada.
      expect(response.parsed_body['secret']).to be_present
      expect(response.parsed_body['secret']).not_to start_with('{"p":')
    end

    it 'inbox que nao e de canal API responde 404' do
      outra = create(:inbox, account: account)
      create(:inbox_member, user: admin, inbox: outra)

      post "/api/v1/accounts/#{account.id}/inboxes/#{outra.id}/reset_secret",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'agente comum nao rotaciona' do
      create(:inbox_member, user: agent, inbox: inbox)
      anterior = channel_api.secret

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/reset_secret",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(channel_api.reload.secret).to eq(anterior)
    end
  end

  # O segredo rotacionado tem de ser o que passa a assinar de verdade. Rotacionar e
  # continuar assinando com o antigo seria o pior dos dois mundos: o cliente troca a chave
  # no lado dele e as entregas passam a falhar a verificacao sem nenhum erro deste lado.
  describe 'depois da rotacao, quem assina e o segredo novo' do
    let(:channel_api) { create(:channel_api, account: account) }
    let(:inbox) { channel_api.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:message) { create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation) }

    before { create(:inbox_member, user: admin, inbox: inbox) }

    it 'o webhook da inbox sai com o segredo novo' do
      anterior = channel_api.secret

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/reset_secret",
           headers: admin.create_new_auth_token, as: :json
      novo = channel_api.reload.secret

      # Sem isto, uma rotacao que falhou deixaria `novo == anterior` e a expectativa
      # seguinte passaria — provando apenas que o listener assina com o segredo de sempre.
      expect(response).to have_http_status(:success)
      expect(novo).not_to eq(anterior)

      expect(WebhookJob).to receive(:perform_later).with(
        channel_api.webhook_url, anything, :api_inbox_webhook,
        hash_including(secret: novo)
      )

      WebhookListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message.reload))
    end
  end
end
