require 'rails_helper'

# Bloco 5.20 / T-I6.4 — o agent bot passa a poder LER a propria conversa.
#
# Hoje `messages#index` nao esta em BOT_ACCESSIBLE_ENDPOINTS: um bot que perde um webhook fica surdo
# em definitivo, porque nao tem como consultar o historico. Ele pode ESCREVER na conversa (create ja
# esta liberado) e nao pode LER o que escreveu — que e a assimetria que este item corrige.
RSpec.describe 'agent bot lendo a propria conversa', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:bot_token) { agent_bot.access_token.token }

  before do
    create(:agent_bot_inbox, agent_bot: agent_bot, inbox: inbox, account: account)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'primeira')
  end

  it 'lista as mensagens da conversa com o token do bot' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
        headers: { api_access_token: bot_token }, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].map { |m| m['content'] }).to include('primeira')
  end

  it 'continua podendo escrever, como antes' do
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: { content: 'resposta do bot' },
         headers: { api_access_token: bot_token }, as: :json

    expect(response).to have_http_status(:success)
  end

  # A liberacao e de leitura da conversa, e nao um passe livre: o que nao esta na lista continua
  # recusado. Sem esta asserção, acrescentar `index` poderia ter aberto outra coisa junto.
  it 'nao ganha acesso a endpoints fora da lista' do
    get "/api/v1/accounts/#{account.id}/contacts",
        headers: { api_access_token: bot_token }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
