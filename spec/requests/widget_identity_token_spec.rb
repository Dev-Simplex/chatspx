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

  # ── Bloco 5.19, segunda entrega: a rota `update` ────────────────────────────────────────────
  #
  # `set_user` nao e a unica porta de identidade deste controller. O `PATCH /widget/contact` e por
  # onde passam o pre-chat com campanha (`PreChatForm.vue`) e o `setCustomAttributes` — e ele ja
  # lia `identity_token`, porque `identified_params` e do controller inteiro, nao da action.
  #
  # O QUE FALTAVA, MEDIDO: um JWT valido chegando aqui aplicava os atributos assinados e carimbava
  # o `identifier`, mas a sessao continuava `hmac_verified: false`. Duas consequencias, e nenhuma
  # delas e cosmetica:
  #
  #   1. O portao de atributo protegido do 4.17 le `@contact_inbox&.hmac_verified?` DENTRO desta
  #      mesma requisicao. Sessao provada por token era tratada como sessao de anonimo.
  #   2. O relatorio de enforcement do 4.15 conta `contact_inboxes.hmac_verified`. Quem identificou
  #      por token nesta rota engordava a coluna de "nao verificadas" para sempre.
  #
  # A decisao e a mesma do `set_user`, e e deliberadamente a MESMA linha: marca quando ha prova.
  # Nao ha prova nova nem prova mais fraca aqui — `valid_hmac?` continua sendo a unica porta.
  describe 'a rota `update` — a outra porta de identidade do mesmo controller' do
    def update_via(params)
      patch '/api/v1/widget/contact',
            params: { website_token: web_widget.website_token }.merge(params),
            headers: { 'X-Auth-Token' => auth_token },
            as: :json
    end

    describe 'quando a inbox esta `desativado`' do
      before { inbox.update!(identity_enforcement: 'desativado') }

      it 'um JWT valido identifica E marca a sessao como verificada, igual ao set_user' do
        update_via(identity_token: valid_token)

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.hmac_verified).to be(true)
        expect(contact_inbox.contact.identifier).to eq('cliente-42')
      end

      it 'os atributos assinados chegam ao contato tambem por aqui' do
        update_via(identity_token: valid_token(email: 'maria@exemplo.com.br', name: 'Maria'))

        contact = contact_inbox.reload.contact
        expect(contact.email).to eq('maria@exemplo.com.br')
        expect(contact.name).to eq('Maria')
      end

      # O aceite do bloco, repetido nesta rota: expirado degrada para anonimo, e nao vira erro.
      it 'um JWT expirado nao verifica, nao identifica e NAO devolve erro' do
        update_via(identity_token: identity_token({ sub: 'cliente-42', exp: 5.minutes.ago.to_i }))

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.hmac_verified).to be(false)
        expect(contact_inbox.contact.identifier).to be_nil
      end

      it 'um JWT assinado com outro segredo nao marca nada' do
        alheio = JWT.encode({ sub: 'cliente-42', exp: 1.hour.from_now.to_i }, 'segredo-errado', 'HS256')

        update_via(identity_token: alheio)

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.hmac_verified).to be(false)
      end
    end

    describe 'quando a inbox esta `observado`' do
      before { inbox.update!(identity_enforcement: 'observado') }

      it 'um JWT valido tira a sessao do relatorio de nao verificadas' do
        update_via(identity_token: valid_token)

        expect(contact_inbox.reload.hmac_verified).to be(true)
        expect(Identity::EnforcementReport.new(inbox: inbox.reload).perform[:unverified][:total]).to eq(0)
      end

      # A CONDICAO RUIM FORCADA. Sem este exemplo, "marca quando ha prova" passaria tambem numa
      # implementacao que marcasse SEMPRE — que e exatamente o defeito que o 4.15 proibiu, porque
      # apagaria o sinal de que o relatorio de enforcement depende.
      it 'o pre-chat anonimo, que nao tem prova nenhuma, continua NAO verificado' do
        update_via(email: 'sem@prova.com.br', name: 'Visitante')

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.hmac_verified).to be(false)
        expect(Identity::EnforcementReport.new(inbox: inbox.reload).perform[:unverified][:total]).to eq(1)
      end
    end

    describe 'quando a inbox esta `obrigatorio`' do
      before { inbox.update!(identity_enforcement: 'obrigatorio') }

      it 'um JWT valido passa, identifica e marca' do
        update_via(identity_token: valid_token)

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.hmac_verified).to be(true)
      end

      it 'um JWT expirado e recusado pela regra do 4.15, e nao por uma regra deste bloco' do
        update_via(identity_token: identity_token({ sub: 'cliente-42', exp: 5.minutes.ago.to_i }))

        expect(response).to have_http_status(:unauthorized)
        expect(contact_inbox.reload.hmac_verified).to be(false)
      end
    end

    # O legado, na rota que ate aqui nunca marcava nada. `identifier_hash` valido e prova de
    # identidade pelo mesmo criterio do `set_user`; tratar a mesma prova de dois jeitos conforme a
    # action e o defeito de juncao que o proprio servico avisa para nao cometer.
    it 'identifier_hash valido tambem marca a sessao nesta rota' do
      inbox.update!(identity_enforcement: 'desativado')
      identificador = 'cliente-legado'
      assinatura = OpenSSL::HMAC.hexdigest('sha256', web_widget.hmac_token, identificador)

      update_via(identifier: identificador, identifier_hash: assinatura)

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(true)
    end

    it 'identifier_hash invalido continua sendo recusado, e nada e marcado' do
      inbox.update!(identity_enforcement: 'desativado')

      update_via(identifier: 'cliente-legado', identifier_hash: 'nao-e-o-hash')

      expect(response).to have_http_status(:unauthorized)
      expect(contact_inbox.reload.hmac_verified).to be(false)
    end

    # O EFEITO DE PRODUTO da marcacao, e nao so o valor da coluna.
    #
    # O portao do 4.17 le `@contact_inbox&.hmac_verified?` DENTRO desta mesma requisicao
    # (`identify_contact`). Enquanto o `update` nao marcava, uma sessao com identidade PROVADA por
    # JWT era tratada como sessao de anonimo e nao conseguia escrever atributo protegido — o pedido
    # passava, o atributo era descartado por chave, e ninguem via nada. Este par de exemplos e o que
    # distingue "a coluna virou true" de "a coluna virou true e serviu para alguma coisa".
    describe 'o portao de atributo protegido do 4.17, na mesma requisicao' do
      before do
        create(:custom_attribute_definition,
               account: account, attribute_key: 'cpf', attribute_model: 'contact_attribute',
               attribute_display_type: 'text', requires_verified_origin: true)
        inbox.update!(identity_enforcement: 'desativado')
      end

      it 'com JWT valido, a chave protegida e GRAVADA' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identity_token: valid_token,
                        custom_attributes: { cpf: '12345678901' } },
              headers: { 'X-Auth-Token' => auth_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.contact.custom_attributes['cpf']).to eq('12345678901')
      end

      it 'sem prova nenhuma, a MESMA chave continua sendo recusada' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token,
                        custom_attributes: { cpf: '12345678901' } },
              headers: { 'X-Auth-Token' => auth_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.contact.custom_attributes['cpf']).to be_nil
      end
    end
  end
end
