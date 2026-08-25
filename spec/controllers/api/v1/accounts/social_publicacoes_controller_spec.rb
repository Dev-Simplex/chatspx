require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::SocialPublicacoesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  it 'nega acesso a agente' do
    get "/api/v1/accounts/#{account.id}/social_publicacoes", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  context 'when it is an authenticated administrator' do
    let!(:publicacao) do
      create(:social_publicacao, account: account, inbox: inbox, legenda: 'Promoção de agosto',
                                 permalink: 'https://instagram.com/reel/abc', publicada_em: 1.day.ago,
                                 sincronizada_em: 1.hour.ago, metricas: { 'like_count' => 218 })
    end

    it 'lista as publicações com legenda, link e métricas' do
      get "/api/v1/accounts/#{account.id}/social_publicacoes", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = response.parsed_body.first
      expect(body['legenda']).to eq('Promoção de agosto')
      expect(body['permalink']).to eq('https://instagram.com/reel/abc')
      expect(body['metricas']['like_count']).to eq(218)
      expect(body['sincronizada']).to be true
    end

    # A diferença entre este número e o `comments_count` da Meta é o que a assinatura não trouxe
    # — comentário anterior a 18/08, ou publicação em colab, que a Meta não entrega.
    it 'conta os comentários capturados, separando cliente de resposta do time' do
      create(:social_comentario, account: account, inbox: inbox, publicacao: publicacao, proprio: false)
      create(:social_comentario, account: account, inbox: inbox, publicacao: publicacao, proprio: false)
      create(:social_comentario, account: account, inbox: inbox, publicacao: publicacao, proprio: true)

      get "/api/v1/accounts/#{account.id}/social_publicacoes", headers: administrator.create_new_auth_token

      body = response.parsed_body.first
      expect(body['comentarios_de_terceiros']).to eq(2)
      expect(body['respostas_da_conta']).to eq(1)
    end

    it 'devolve zero para publicação sem comentário capturado' do
      get "/api/v1/accounts/#{account.id}/social_publicacoes", headers: administrator.create_new_auth_token

      body = response.parsed_body.first
      expect(body['comentarios_de_terceiros']).to eq(0)
      expect(body['respostas_da_conta']).to eq(0)
    end

    it 'não enxerga publicação de outra conta' do
      outra = create(:account)
      create(:social_publicacao, account: outra, inbox: create(:inbox, account: outra),
                                 legenda: 'de outro cliente')

      get "/api/v1/accounts/#{account.id}/social_publicacoes", headers: administrator.create_new_auth_token

      expect(response.parsed_body.pluck('legenda')).not_to include('de outro cliente')
    end
  end
end
