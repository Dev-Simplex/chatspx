require 'rails_helper'

# Bloco 5.19 — o JWT entra na MESMA maquina de estados do 4.15, nunca num caminho paralelo.
#
# Cada exemplo afirma duas coisas: o que a resposta fez com a sessao (quebrou ou nao) e o que ficou
# no banco (identificou? marcou como verificada?). E o mesmo par do spec do 4.15, de proposito.
RSpec.describe 'identidade por JWT no widget', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  let(:visitor) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: visitor, inbox: inbox, hmac_verified: false) }
  let(:auth_token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  def identity_token(payload)
    JWT.encode(payload, web_widget.hmac_token, 'HS256')
  end

  def valid_token(sub: 'cliente-42', **extra)
    identity_token({ sub: sub, exp: 1.hour.from_now.to_i }.merge(extra))
  end

  def identify_via(params)
    patch '/api/v1/widget/contact/set_user',
          params: { website_token: web_widget.website_token }.merge(params),
          headers: { 'X-Auth-Token' => auth_token },
          as: :json
  end

  describe 'desativado — o estado da maioria da frota' do
    before { inbox.update!(identity_enforcement: 'desativado') }

    it 'um JWT valido identifica e marca a sessao como verificada' do
      identify_via(identity_token: valid_token)

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(true)
      expect(contact_inbox.contact.identifier).to eq('cliente-42')
    end

    it 'os atributos que vieram DENTRO do token assinado chegam ao contato' do
      identify_via(identity_token: valid_token(email: 'maria@exemplo.com.br', name: 'Maria'))

      contact = contact_inbox.reload.contact
      expect(contact.email).to eq('maria@exemplo.com.br')
      expect(contact.name).to eq('Maria')
    end

    # O ACEITE do bloco: expirado degrada para anonimo, e nao vira erro.
    it 'um JWT expirado nao identifica, nao verifica e NAO devolve erro' do
      identify_via(identity_token: identity_token({ sub: 'cliente-42', exp: 5.minutes.ago.to_i }))

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(false)
      expect(contact_inbox.contact.identifier).to be_nil
    end

    it 'um JWT assinado por outra inbox nao identifica ninguem' do
      other_widget = create(:channel_widget, account: account)
      alheio = JWT.encode({ sub: 'cliente-42', exp: 1.hour.from_now.to_i }, other_widget.hmac_token, 'HS256')

      identify_via(identity_token: alheio)

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(false)
      expect(contact_inbox.contact.identifier).to be_nil
    end

    it 'o token vence o corpo da requisicao, porque so ele e prova' do
      identify_via(identity_token: valid_token(sub: 'assinado'), identifier: 'chutado')

      expect(contact_inbox.reload.contact.identifier).to eq('assinado')
    end
  end

  describe 'o HMAC legado continua funcionando, intacto' do
    before { inbox.update!(identity_enforcement: 'desativado') }

    it 'identifier_hash valido identifica e marca a sessao como verificada' do
      identifier = 'cliente-legado'
      hash = OpenSSL::HMAC.hexdigest('sha256', web_widget.hmac_token, identifier)

      identify_via(identifier: identifier, identifier_hash: hash)

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(true)
      expect(contact_inbox.contact.identifier).to eq(identifier)
    end

    it 'identifier_hash invalido continua sendo recusado' do
      identify_via(identifier: 'cliente-legado', identifier_hash: 'nao-e-o-hash')

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'observado — conta sem recusar' do
    before { inbox.update!(identity_enforcement: 'observado') }

    it 'um JWT valido conta como IDENTIFICADO: a sessao fica verificada' do
      identify_via(identity_token: valid_token)

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(true)
    end

    it 'quem chega SEM token nenhum continua passando — nenhuma sessao quebra' do
      patch '/api/v1/widget/contact',
            params: { website_token: web_widget.website_token, email: 'sem@prova.com' },
            headers: { 'X-Auth-Token' => auth_token },
            as: :json

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(false)
    end

    it 'a sessao identificada por JWT sai do relatorio de nao verificadas' do
      identify_via(identity_token: valid_token(email: 'maria@exemplo.com.br'))

      report = Identity::EnforcementReport.new(inbox: inbox.reload).perform

      expect(report[:unverified][:total]).to eq(0)
    end
  end

  describe 'obrigatorio — a decisao continua sendo do 4.15' do
    before { inbox.update!(identity_enforcement: 'obrigatorio') }

    it 'um JWT valido identifica, e a sessao passa' do
      identify_via(identity_token: valid_token)

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(true)
    end

    # Aqui esta a fronteira, e ela e do 4.15, nao deste bloco: sem prova, a inbox estrita recusa.
    # O JWT expirado nao inventa uma recusa propria nem uma permissao propria — ele simplesmente
    # nao prova nada, e a resposta e EXATAMENTE a mesma de quem nao mandou token nenhum.
    it 'um JWT expirado produz a mesma resposta que nao mandar token nenhum' do
      identify_via(identity_token: identity_token({ sub: 'cliente-42', exp: 5.minutes.ago.to_i }))
      com_token_expirado = response.status

      identify_via({})
      sem_token = response.status

      expect(com_token_expirado).to eq(sem_token)
      expect(contact_inbox.reload.hmac_verified).to be(false)
    end
  end

  describe 'o pre-chat anonimo, que o visitante nao tem como assinar' do
    before { inbox.update!(identity_enforcement: 'obrigatorio') }

    # A ressalva herdada do 4.15: o segredo mora no servidor do cliente, entao o visitante do
    # pre-chat NUNCA consegue assinar. O JWT nao muda isso, e este exemplo existe para provar que
    # este bloco nao fechou essa porta sem querer.
    it 'continua aceitando nome e atributos sem identidade, como antes deste bloco' do
      patch '/api/v1/widget/contact',
            params: { website_token: web_widget.website_token, name: 'Visitante' },
            headers: { 'X-Auth-Token' => auth_token },
            as: :json

      expect(response).to have_http_status(:success)
    end
  end
end
