require 'rails_helper'

# O único caminho de escrita do módulo. O que estes exemplos travam é que NADA sai sem passar
# pelo portão do piloto — inclusive quando o clique é humano.
RSpec.describe 'Api::V1::Accounts::SocialComentariosController#responder', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_instagram, account: account, instagram_id: '17841468839878751') }
  let(:inbox) { channel.inbox }
  let!(:comentario) do
    create(:social_comentario, account: account, inbox: inbox, external_id: 'c-1',
                               autor_username: 'pauloseze', publicacao_external_id: 'pub-1')
  end

  def configurar(config)
    account.update!(settings: (account.settings || {}).merge('social_reply' => config))
  end

  def responder(forma, texto: 'oie', usuario: administrator)
    post "/api/v1/accounts/#{account.id}/social_comentarios/#{comentario.id}/responder",
         params: { forma: forma, texto: texto }, headers: usuario.create_new_auth_token
  end

  it 'nega a agente' do
    configurar('privada' => true, 'allowlist' => ['pauloseze'])

    responder('privada', usuario: agent)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'recusa sem enviar nada quando a conta não configurou a forma' do
    responder('privada')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['erro']).to eq('forma_desligada')
  end

  # A razão de existir do piloto: clicar em responder num comentário de cliente real não envia.
  it 'recusa autor fora da allowlist, mesmo com clique humano' do
    configurar('privada' => true, 'allowlist' => ['pauloseze'])
    comentario.update!(autor_username: 'cliente_de_verdade')

    responder('privada')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['erro']).to eq('fora_do_piloto')
  end

  it 'recusa texto vazio antes de falar com a Meta' do
    configurar('privada' => true, 'allowlist' => ['pauloseze'])

    responder('privada', texto: '   ')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['erro']).to eq('texto_vazio')
  end

  context 'when the gate allows it' do
    before { configurar('publica' => true, 'privada' => true, 'allowlist' => ['pauloseze']) }

    it 'envia a privada pelo endpoint de mensagens e grava o id devolvido' do
      stub = stub_request(:post, %r{graph\.instagram\.com/v22\.0/17841468839878751/messages})
             .to_return(status: 200, body: { message_id: 'aWdt-99' }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      responder('privada')

      expect(response).to have_http_status(:success)
      expect(stub).to have_been_requested
      expect(comentario.reload.respostas_registradas.dig('privada', 'external_id')).to eq('aWdt-99')
    end

    it 'envia a pública pelo endpoint de replies do comentário' do
      stub = stub_request(:post, %r{graph\.instagram\.com/v22\.0/c-1/replies})
             .to_return(status: 200, body: { id: '17999' }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      responder('publica')

      expect(response).to have_http_status(:success)
      expect(stub).to have_been_requested
      expect(comentario.reload.respostas_registradas.dig('publica', 'external_id')).to eq('17999')
    end

    # A privada é uma por comentário: um segundo clique não pode gastar a chance de novo.
    it 'não reenvia o que a Meta já aceitou' do
      stub_request(:post, /graph\.instagram\.com/).to_return(status: 200, body: { message_id: 'x' }.to_json,
                                                             headers: { 'Content-Type' => 'application/json' })
      responder('privada')
      responder('privada')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['erro']).to eq('ja_respondido')
      # Regex do endpoint de mensagens, e não de `graph.instagram.com` inteiro: criar o canal já
      # dispara um POST em `/subscribed_apps` (o `subscribe` do `after_create_commit`), que
      # entraria na contagem e esconderia o que este exemplo mede.
      expect(a_request(:post, %r{graph\.instagram\.com/v22\.0/17841468839878751/messages}))
        .to have_been_made.once
    end

    # A Meta devolve 200 com `error` no corpo em alguns caminhos — status sozinho não basta.
    it 'trata erro no corpo de uma resposta 200 como falha, e grava o erro' do
      stub_request(:post, /graph\.instagram\.com/)
        .to_return(status: 200, body: { error: { code: 100, error_subcode: 2_534_014, message: 'não achou' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      responder('privada')

      expect(response).to have_http_status(:unprocessable_entity)
      registro = comentario.reload.respostas_registradas['privada']
      expect(registro['external_id']).to be_nil
      expect(registro['erro']).to include('2534014')
    end

    it 'deixa tentar de novo depois de uma falha' do
      stub_request(:post, /graph\.instagram\.com/).to_return(status: 400, body: { error: { code: 1 } }.to_json,
                                                             headers: { 'Content-Type' => 'application/json' })
      responder('privada')
      expect(response).to have_http_status(:unprocessable_entity)

      stub_request(:post, /graph\.instagram\.com/).to_return(status: 200, body: { message_id: 'ok-2' }.to_json,
                                                             headers: { 'Content-Type' => 'application/json' })
      responder('privada')

      expect(response).to have_http_status(:success)
    end

    it 'não responde comentário de outra conta' do
      alheio = create(:social_comentario, account: create(:account), inbox: create(:inbox))

      post "/api/v1/accounts/#{account.id}/social_comentarios/#{alheio.id}/responder",
           params: { forma: 'privada', texto: 'oie' }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end
end
