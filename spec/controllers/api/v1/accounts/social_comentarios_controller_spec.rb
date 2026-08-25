require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::SocialComentariosController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:publicacao) do
    create(:social_publicacao, account: account, inbox: inbox, external_id: 'pub-1',
                               legenda: 'Promoção de agosto')
  end

  def comentario(atributos = {})
    create(:social_comentario, {
      account: account, inbox: inbox, publicacao: publicacao,
      publicacao_external_id: publicacao.external_id
    }.merge(atributos))
  end

  it 'nega acesso a agente' do
    get "/api/v1/accounts/#{account.id}/social_comentarios", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  context 'when it is an authenticated administrator' do
    it 'lista os comentários de clientes com o contexto da publicação' do
      comentario(autor_username: 'nilgloria', texto: 'No domingo que horas abre a loja')

      get "/api/v1/accounts/#{account.id}/social_comentarios", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first['autor_username']).to eq('nilgloria')
      expect(body.first['publicacao']['legenda']).to eq('Promoção de agosto')
    end

    # 22 das 51 entregas medidas eram da própria conta. Elas ficam gravadas, mas a lista que o
    # operador abre é a das perguntas — as respostas do time só entram sob pedido.
    it 'esconde as respostas da própria conta por padrão' do
      comentario(autor_username: 'cliente')
      comentario(proprio: true, autor_username: 'bigstoreutilidades', texto: '@cliente oie')

      get "/api/v1/accounts/#{account.id}/social_comentarios", headers: administrator.create_new_auth_token

      expect(response.parsed_body.pluck('proprio')).to eq([false])
    end

    it 'inclui as respostas da conta quando pedido' do
      comentario(autor_username: 'cliente')
      comentario(proprio: true, autor_username: 'bigstoreutilidades', texto: '@cliente oie')

      get "/api/v1/accounts/#{account.id}/social_comentarios?incluir_proprios=true",
          headers: administrator.create_new_auth_token

      expect(response.parsed_body.length).to eq(2)
    end

    # O ponto da tela: dizer o que falta responder. A resposta da conta está escondida da
    # listagem, então a inferência precisa olhar além da página filtrada.
    it 'marca respondido mesmo com a resposta fora da listagem' do
      comentario(autor_username: 'vanderlea', texto: 'qual o contato da loja?')
      comentario(proprio: true, autor_username: 'bigstoreutilidades', texto: '@vanderlea oie, bom dia')

      get "/api/v1/accounts/#{account.id}/social_comentarios", headers: administrator.create_new_auth_token

      expect(response.parsed_body.first['respondido']).to be true
    end

    it 'mostra como não respondido quem ninguém endereçou' do
      comentario(autor_username: 'esquecido')

      get "/api/v1/accounts/#{account.id}/social_comentarios", headers: administrator.create_new_auth_token

      expect(response.parsed_body.first['respondido']).to be false
    end

    it 'filtra por publicação' do
      outra = create(:social_publicacao, account: account, inbox: inbox, external_id: 'pub-2')
      comentario(autor_username: 'daqui')
      create(:social_comentario, account: account, inbox: inbox, publicacao: outra,
                                 publicacao_external_id: outra.external_id, autor_username: 'dali')

      get "/api/v1/accounts/#{account.id}/social_comentarios?publicacao_id=#{publicacao.id}",
          headers: administrator.create_new_auth_token

      expect(response.parsed_body.pluck('autor_username')).to eq(['daqui'])
    end

    it 'não enxerga comentário de outra conta' do
      outra_conta = create(:account)
      create(:social_comentario, account: outra_conta, inbox: create(:inbox, account: outra_conta),
                                 autor_username: 'de-outro-cliente')

      get "/api/v1/accounts/#{account.id}/social_comentarios", headers: administrator.create_new_auth_token

      expect(response.parsed_body.pluck('autor_username')).not_to include('de-outro-cliente')
    end

    it 'devolve os mais recentes primeiro' do
      comentario(autor_username: 'antigo', comentado_em: 2.days.ago)
      comentario(autor_username: 'recente', comentado_em: 1.hour.ago)

      get "/api/v1/accounts/#{account.id}/social_comentarios", headers: administrator.create_new_auth_token

      expect(response.parsed_body.pluck('autor_username')).to eq(%w[recente antigo])
    end
  end
end
