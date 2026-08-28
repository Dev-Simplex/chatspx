require 'rails_helper'

# Contrato de LEITURA do cofre de credenciais, medido na serializacao REAL.
#
# Este spec existe porque a mesma tela ja quebrou TRES vezes na mesma junta, e as tres passaram
# por todos os testes que existiam:
#
#   1. o front chamava /tracking_credentials (plural) contra `resource :tracking_credential`;
#   2. o front fazia PUT numa rota POR CHAVE que nunca existiu;
#   3. o front lia `data.credentials`, um envelope que o jbuilder nunca devolveu — a tela
#      mostrava "nao configurado" com o token gravado.
#
# As tres sobreviveram porque cada lado testava a si mesmo: o spec do front DUBLA o axios (e o
# dublê era escrito com a forma imaginada), e o spec do backend chama o controller direto. O
# encontro dos dois nao tinha dono.
#
# Aqui a resposta e a de verdade: request spec, jbuilder de verdade, JSON de verdade. As
# assercoes descrevem exatamente o que `useTrackingCredentials.js` LE.
# O que o front consome. Se alguem acrescentar segredo ao modelo, acrescente aqui tambem.
CHAVES_QUE_O_FRONT_LE = %w[meta_access_token ga4_api_secret].freeze

RSpec.describe 'Contrato de leitura do cofre de credenciais', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }

  def corpo
    response.parsed_body
  end

  before do
    get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_credential",
        headers: admin.create_new_auth_token, as: :json
  end

  it 'responde 200' do
    expect(response).to have_http_status(:success)
  end

  it 'NAO envelopa em `credentials` — as chaves ficam na RAIZ' do
    expect(corpo).not_to have_key('credentials')
    expect(corpo.keys).to include(*CHAVES_QUE_O_FRONT_LE)
  end

  CHAVES_QUE_O_FRONT_LE.each do |chave|
    it "devolve `#{chave}` no formato que o front le: configured + last_four" do
      expect(corpo[chave]).to be_a(Hash)
      expect(corpo[chave].keys).to contain_exactly('configured', 'last_four')
      expect(corpo[chave]['configured']).to be_in([true, false])
    end
  end

  it 'nunca devolve o valor do segredo, nem vazio nem preenchido' do
    credencial = TrackingCredential.find_or_initialize_by(account: account, inbox: inbox)
    credencial.update!(meta_access_token: 'SEGREDO-QUE-NAO-PODE-SAIR-1234')

    get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/tracking_credential",
        headers: admin.create_new_auth_token, as: :json

    expect(response.body).not_to include('SEGREDO-QUE-NAO-PODE-SAIR')
    expect(corpo['meta_access_token']['configured']).to be(true)
    expect(corpo['meta_access_token']['last_four']).to eq('1234')
  end

  it 'a lista de chaves nao esta vazia — senao esta guarda mede zero' do
    expect(CHAVES_QUE_O_FRONT_LE).not_to be_empty
  end
end
