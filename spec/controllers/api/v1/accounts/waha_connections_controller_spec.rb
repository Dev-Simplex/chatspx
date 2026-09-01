require 'rails_helper'

# Excluir uma conexão de número apagava a CAIXA junto, sempre, e com ela conversas e mensagens em
# cascata (`dependent: :destroy_async` no Inbox). Medido na Catatau em 27/08/2026: a conexão
# "Vendas" arrastaria 69 conversas e 7.621 mensagens, sem desfazer — e o único aviso dizia
# "a caixa de entrada associada também será excluída", que ninguém lê como "perco o histórico".
RSpec.describe 'Api::V1::Accounts::WahaConnections', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:sessao) { 'VendasTeste' }
  let!(:inbox) { create(:inbox, account: account, waha_session_name: sessao) }

  let(:url) { "/api/v1/accounts/#{account.id}/waha_connections/#{sessao}" }
  let(:waha) { instance_double(Waha::ApiService) }

  before do
    allow(Waha::ApiService).to receive(:new).and_return(waha)
    allow(waha).to receive(:delete_session).with(sessao)
  end

  def conversa_com_mensagem
    conversa = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversa)
    conversa
  end

  describe 'DELETE sem pedir para apagar a caixa (o padrão)' do
    it 'apaga a sessão no WAHA' do
      expect(waha).to receive(:delete_session).with(sessao)

      delete url, headers: admin.create_new_auth_token
    end

    it 'MANTÉM a caixa de entrada' do
      delete url, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end

    it 'mantém conversas e mensagens' do
      conversa = conversa_com_mensagem

      delete url, headers: admin.create_new_auth_token

      expect(Conversation.exists?(conversa.id)).to be(true)
      expect(conversa.messages.count).to eq(1)
    end

    # É o que faz a conexão sumir da tela: o #index parte das sessões do WAHA e casa por este
    # campo. Sem limpar, a caixa continuaria apontando para uma sessão que já não existe.
    it 'desvincula a caixa da sessão' do
      delete url, headers: admin.create_new_auth_token

      expect(inbox.reload.waha_session_name).to be_nil
    end

    it 'diz na resposta que a caixa foi preservada' do
      delete url, headers: admin.create_new_auth_token

      expect(response.parsed_body['inbox_deleted']).to be(false)
    end
  end

  describe 'DELETE pedindo para apagar a caixa' do
    it 'apaga a caixa quando delete_inbox=true' do
      delete url, params: { delete_inbox: true }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(Inbox.exists?(inbox.id)).to be(false)
      expect(response.parsed_body['inbox_deleted']).to be(true)
    end

    it 'aceita as formas usuais de sim' do
      %w[true 1 yes on TRUE].each do |valor|
        caixa = create(:inbox, account: account, waha_session_name: "s-#{valor}")
        allow(waha).to receive(:delete_session).with("s-#{valor}")

        delete "/api/v1/accounts/#{account.id}/waha_connections/s-#{valor}",
               params: { delete_inbox: valor }, headers: admin.create_new_auth_token

        expect(Inbox.exists?(caixa.id)).to be(false), "delete_inbox=#{valor} deveria apagar"
      end
    end
  end

  # Fechado no NÃO: errar para "manter" custa uma caixa órfã, que se apaga depois; errar para
  # "apagar" custa milhares de mensagens que não voltam.
  describe 'o parâmetro erra para o lado seguro' do
    # `talvez` e `null` estao aqui porque o ActiveModel::Type::Boolean trata QUALQUER string
    # desconhecida como TRUE — um typo no cliente apagaria o historico.
    [nil, '', 'false', '0', 'no', 'off', 'talvez', 'null', 'undefined', 'TRUEE'].each do |valor|
      it "não apaga a caixa com delete_inbox=#{valor.inspect}" do
        params = valor.nil? ? {} : { delete_inbox: valor }

        delete url, params: params, headers: admin.create_new_auth_token

        expect(Inbox.exists?(inbox.id)).to be(true)
      end
    end

    # Um cliente antigo (aba aberta antes do deploy) não manda o parâmetro. Antes disto ele
    # apagava a caixa; agora ele preserva.
    it 'cliente que não conhece o parâmetro preserva o histórico' do
      conversa = conversa_com_mensagem

      delete url, headers: admin.create_new_auth_token

      expect(Conversation.exists?(conversa.id)).to be(true)
    end
  end

  describe 'autorização' do
    it 'nega para agente comum' do
      delete url, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end

    it 'nega sem autenticação' do
      delete url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'não encontra sessão de outra conta' do
      outra = create(:inbox, account: create(:account), waha_session_name: 'DeOutraConta')

      delete "/api/v1/accounts/#{account.id}/waha_connections/DeOutraConta",
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(Inbox.exists?(outra.id)).to be(true)
    end
  end

  # Medido na Catatau em 27/08/2026: a sessao "Vendas" travou num lock interno do WAHA
  # ("async-lock timed out in queue Vendas") e o DELETE respondia 500 mesmo chamado DIRETO, sem
  # passar por aqui. O controller devolvia 422 e nao fazia mais nada, entao a conexao ficava
  # IMPOSSIVEL de remover pela tela ate alguem consertar o outro lado.
  describe 'quando o WAHA falha' do
    before { allow(waha).to receive(:delete_session).and_raise(Waha::ApiService::Error, 'boom') }

    it 'nao deixa o operador preso: desvincula a caixa mesmo assim' do
      delete url, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(inbox.reload.waha_session_name).to be_nil
    end

    it 'avisa que a sessao ficou para tras no servidor' do
      delete url, headers: admin.create_new_auth_token

      expect(response.parsed_body['waha_session_deleted']).to be(false)
    end

    # A sessao continua viva la e ainda pode voltar a receber. Destruir o historico nesse cenario
    # e o pior desfecho possivel, e o operador nao pediu "apague mesmo se der errado".
    it 'NAO apaga a caixa mesmo com delete_inbox=true' do
      conversa = conversa_com_mensagem

      delete url, params: { delete_inbox: true }, headers: admin.create_new_auth_token

      expect(Inbox.exists?(inbox.id)).to be(true)
      expect(Conversation.exists?(conversa.id)).to be(true)
      expect(response.parsed_body['inbox_deleted']).to be(false)
    end
  end

  # O estado desejado ja e esse: nao ha o que apagar.
  describe 'quando a sessao ja nao existe no WAHA' do
    before { allow(waha).to receive(:delete_session).and_raise(Waha::ApiService::NotFoundError) }

    it 'trata como sucesso e apaga a caixa se foi pedido' do
      delete url, params: { delete_inbox: true }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['waha_session_deleted']).to be(true)
      expect(Inbox.exists?(inbox.id)).to be(false)
    end
  end
end
