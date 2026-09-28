require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Suggestions', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:outro_agente) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/suggestions" }

  describe 'POST /suggestions' do
    it 'nega sem autenticacao' do
      post url, params: { content: 'ideia' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'grava a sugestao com nome e empresa vindos do login' do
      post url, params: { content: 'Seria bom filtrar por etiqueta.' }, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:success)
      suggestion = Suggestion.last
      expect(suggestion.content).to eq('Seria bom filtrar por etiqueta.')
      expect(suggestion.name).to eq(agente.name)
      expect(suggestion.company).to eq(account.name)
      expect(suggestion.source).to eq('in_app')
      expect(suggestion.status).to eq('nova')
      expect(suggestion.user_id).to eq(agente.id)
    end

    it 'recusa sugestao sem texto e nao grava nada' do
      expect do
        post url, params: { content: '' }, headers: agente.create_new_auth_token
      end.not_to change(Suggestion, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'recusa anexo que nao e foto nem video' do
      arquivo = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/attachment.pdf'), 'application/pdf')

      expect do
        post url, params: { content: 'com anexo', media: arquivo }, headers: agente.create_new_auth_token
      end.not_to change(Suggestion, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /suggestions' do
    it 'devolve so as minhas, da mais recente para a mais antiga' do
      minha_antiga = create(:suggestion, account: account, user: agente, content: 'antiga')
      minha_antiga.update!(created_at: 2.days.ago)
      minha_nova = create(:suggestion, account: account, user: agente, content: 'nova')
      create(:suggestion, account: account, user: outro_agente, content: 'do colega')

      get url, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:success)
      conteudos = response.parsed_body['payload'].pluck('content')
      expect(conteudos).to eq(%w[nova antiga])
      expect(conteudos).not_to include('do colega')
      expect(response.parsed_body['payload'].first['id']).to eq(minha_nova.id)
    end

    it 'nao vaza sugestao de outra conta' do
      outra_conta = create(:account)
      create(:suggestion, account: outra_conta, user: create(:user, account: outra_conta, role: :agent))

      get url, headers: agente.create_new_auth_token

      expect(response.parsed_body['payload']).to be_empty
    end
  end
end
