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

    it 'administrador ve as sugestoes de toda a conta, com o nome de quem mandou' do
      admin = create(:user, account: account, role: :administrator)
      create(:suggestion, account: account, user: agente, name: agente.name, content: 'do agente')
      create(:suggestion, account: account, user: admin, name: admin.name, content: 'do admin')
      create(:suggestion, account: create(:account), content: 'de outra conta')

      get url, headers: admin.create_new_auth_token

      payload = response.parsed_body['payload']
      expect(payload.pluck('content')).to contain_exactly('do agente', 'do admin')
      expect(payload.pluck('name')).to include(agente.name)
      expect(response.parsed_body['meta']['all_account']).to be(true)
    end

    context 'with a public link suggestion' do
      before { create(:suggestion, account: nil, user: nil, source: :public_link, name: 'Kaio', company: 'Loja K', content: 'do link') }

      it 'so o admin da conta autora (deploy de casa, conta 3) ve as do link' do
        autora = Account.find_by(id: 3) || create(:account, id: 3)
        admin = create(:user, account: autora, role: :administrator)

        with_modified_env FRONTEND_URL: 'https://chat.simplexsolucoes.com.br' do
          get '/api/v1/accounts/3/suggestions', headers: admin.create_new_auth_token
        end

        do_link = response.parsed_body['payload'].find { |s| s['content'] == 'do link' }
        expect(do_link).to include('source' => 'public_link', 'company' => 'Loja K', 'name' => 'Kaio')
      end

      it 'admin de outra conta nao ve as do link' do
        admin = create(:user, account: account, role: :administrator)

        with_modified_env FRONTEND_URL: 'https://chat.simplexsolucoes.com.br' do
          get url, headers: admin.create_new_auth_token
        end

        expect(response.parsed_body['payload'].pluck('content')).not_to include('do link')
      end
    end

    # No fork, supervisor e ADMINISTRADOR com times (AccountUser#console_role): nao pode ver as dos outros.
    it 'supervisor ve so as proprias' do
      supervisor = create(:user, account: account, role: :administrator)
      team = create(:team, account: account)
      create(:team_member, team: team, user: agente)
      AccountUser.find_by(account: account, user: supervisor).update!(supervised_team_ids: [team.id])
      create(:suggestion, account: account, user: agente, content: 'do agente')
      create(:suggestion, account: account, user: supervisor, content: 'do supervisor')

      get url, headers: supervisor.create_new_auth_token

      expect(response.parsed_body['payload'].pluck('content')).to eq(['do supervisor'])
      expect(response.parsed_body['meta']['all_account']).to be(false)
    end

    it 'nao vaza sugestao de outra conta' do
      outra_conta = create(:account)
      create(:suggestion, account: outra_conta, user: create(:user, account: outra_conta, role: :agent))

      get url, headers: agente.create_new_auth_token

      expect(response.parsed_body['payload']).to be_empty
    end
  end
end
