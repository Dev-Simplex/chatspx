require 'rails_helper'

RSpec.describe '/api/v1/widget/contacts', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: 'test@test.com', phone_number: '+745623239') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:payload) { { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id } }
  let(:token) { Widget::TokenService.new(payload: payload).generate_token }

  describe 'PATCH /api/v1/widget/contact' do
    let(:params) { { website_token: web_widget.website_token, identifier: 'test' } }

    context 'with invalid website token' do
      it 'returns unauthorized' do
        patch '/api/v1/widget/contact', params: { website_token: '' }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with correct website token' do
      let(:identify_action) { double }

      before do
        allow(ContactIdentifyAction).to receive(:new).and_return(identify_action)
        allow(identify_action).to receive(:perform).and_return(contact)
      end

      it 'calls contact identify' do
        patch '/api/v1/widget/contact',
              params: params,
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:success)
        # `verified_origin` (bloco 4.17) diz se a sessao teve a identidade conferida por
        # assinatura. Aqui a sessao nasce sem verificacao, entao false.
        #
        # `identity_enforcement` (bloco 1.11, porta 5) e o estado RESOLVIDO da inbox, e vai
        # SEMPRE — inclusive `desativado`, que e o valor desta inbox. Ele e o que arma o
        # `refuse_merge_under_enforcement?`; enquanto este chamador o omitia, a action lia
        # `nil` e o portao ficava inerte no endpoint que o bloco endureceu.
        expected_params = { contact: contact, params: params, discard_invalid_attrs: true,
                            identity_enforcement: 'desativado', verified_origin: false }
        expect(ContactIdentifyAction).to have_received(:new).with(expected_params)
        expect(identify_action).to have_received(:perform)
      end
    end

    context 'with update contact' do
      let(:params) { { website_token: web_widget.website_token } }

      it 'dont update phone number if invalid phone number passed' do
        patch '/api/v1/widget/contact',
              params: params.merge({ phone_number: '45623239' }),
              headers: { 'X-Auth-Token' => token },
              as: :json
        body = response.parsed_body
        expect(body['has_phone_number']).to be true
        contact.reload
        expect(contact.phone_number).to eq('+745623239')
        expect(response).to have_http_status(:success)
      end

      it 'update phone number if valid phone number passed' do
        patch '/api/v1/widget/contact',
              params: params.merge({ phone_number: '+245623239' }),
              headers: { 'X-Auth-Token' => token },
              as: :json
        body = response.parsed_body
        expect(body['has_phone_number']).to be true
        contact.reload
        expect(contact.phone_number).to eq('+245623239')
        expect(response).to have_http_status(:success)
      end

      it 'dont update email if invalid email passed' do
        patch '/api/v1/widget/contact',
              params: params.merge({ email: 'test@' }),
              headers: { 'X-Auth-Token' => token },
              as: :json
        body = response.parsed_body
        expect(body['has_email']).to be true
        contact.reload
        expect(contact.email).to eq('test@test.com')
        expect(response).to have_http_status(:success)
      end

      it 'dont update email if empty value email passed' do
        patch '/api/v1/widget/contact',
              params: params.merge({ email: '' }),
              headers: { 'X-Auth-Token' => token },
              as: :json
        body = response.parsed_body
        expect(body['has_email']).to be true
        contact.reload
        expect(contact.email).to eq('test@test.com')
        expect(response).to have_http_status(:success)
      end

      it 'dont update email if nil value email passed' do
        patch '/api/v1/widget/contact',
              params: params.merge({ email: nil }),
              headers: { 'X-Auth-Token' => token },
              as: :json
        body = response.parsed_body
        expect(body['has_email']).to be true
        contact.reload
        expect(contact.email).to eq('test@test.com')
        expect(response).to have_http_status(:success)
      end

      it 'update email if valid email passed' do
        patch '/api/v1/widget/contact',
              params: params.merge({ email: 'test-1@test.com' }),
              headers: { 'X-Auth-Token' => token },
              as: :json
        body = response.parsed_body
        expect(body['has_email']).to be true
        contact.reload
        expect(contact.email).to eq('test-1@test.com')
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /api/v1/widget/contact with HMAC enforcement' do
    let(:web_widget) { create(:channel_widget, account: account, hmac_mandatory: true) }
    let!(:victim) { create(:contact, account: account, identifier: 'victim-identifier', name: 'Victim') }
    let(:correct_identifier_hash) { OpenSSL::HMAC.hexdigest('sha256', web_widget.hmac_token, 'victim-identifier') }

    context 'when an identifier is supplied on a mandatory-hmac inbox' do
      it 'rejects when identifier_hash is omitted' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identifier: 'victim-identifier', name: 'Attacker' },
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(victim.reload.name).to eq('Victim')
      end

      it 'rejects when identifier_hash is blank' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identifier: 'victim-identifier', identifier_hash: '', name: 'Attacker' },
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(victim.reload.name).to eq('Victim')
      end

      it 'rejects when identifier_hash is null' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identifier: 'victim-identifier', identifier_hash: nil, name: 'Attacker' },
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(victim.reload.name).to eq('Victim')
      end

      it 'rejects when identifier_hash is invalid' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identifier: 'victim-identifier',
                        identifier_hash: 'DEFINITELY_INVALID_AAAAA_NOT_A_REAL_HMAC', name: 'Attacker' },
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(victim.reload.name).to eq('Victim')
      end

      it 'succeeds when a valid identifier_hash is provided' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identifier: 'victim-identifier',
                        identifier_hash: correct_identifier_hash, name: 'Legit' },
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:success)
      end
    end

    context 'when no identifier is supplied (anonymous prechat update)' do
      it 'allows updating the name without an identifier_hash' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, name: 'Prechat User' },
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(contact.reload.name).to eq('Prechat User')
      end
    end
  end

  # BLOCO 1.11 — HMAC, portas 1 e 2 (B5)
  #
  # Porta 1: PATCH /widget/contact aceitava escrita de identidade sem assinatura.
  # Porta 2: should_verify_hmac? desligava a checagem quando custom_attributes
  #          vinha presente e identifier vinha em branco.
  #
  # O impacto das duas e o mesmo e nao e "atributo errado": ContactIdentifyAction
  # faz merge_if_existing_email_contact / _phone_number_contact quando identifier
  # esta em branco (contact_identify_action.rb:36-47,72-85). O merge MOVE o
  # contact_inbox da sessao anonima para o contato da vitima, ou seja, entrega ao
  # chamador a sessao de widget da vitima e o historico de conversas dela.
  describe 'BLOCO 1.11 - takeover de contato por merge sem HMAC' do
    let(:web_widget) { create(:channel_widget, account: account, hmac_mandatory: true) }
    let!(:victim) do
      create(:contact, account: account, identifier: 'victim-identifier', name: 'Victim',
                       email: 'victim@corp.com', phone_number: '+551199990000')
    end
    let(:attacker) { create(:contact, account: account, name: 'Anon') }
    let(:attacker_inbox) { create(:contact_inbox, contact: attacker, inbox: web_widget.inbox) }
    let(:attacker_token) do
      Widget::TokenService.new(payload: { source_id: attacker_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
    end

    # A prova do takeover: o contact_inbox da sessao continua apontando para o
    # contato anonimo, e a vitima nao ganhou a sessao do atacante.
    def expect_no_takeover
      expect(attacker_inbox.reload.contact_id).to eq(attacker.id)
      expect(victim.reload.contact_inboxes.pluck(:source_id)).not_to include(attacker_inbox.source_id)
    end

    context 'when porta 1: PATCH /widget/contact sem assinatura, em inbox com hmac obrigatorio' do
      it 'nao altera o contato quando o e-mail da vitima e enviado sem identifier_hash' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, email: 'victim@corp.com', name: 'Attacker' },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(victim.reload.name).to eq('Victim')
        expect_no_takeover
      end

      it 'nao altera o contato quando o telefone da vitima e enviado sem identifier_hash' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, phone_number: '+551199990000' },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect_no_takeover
      end
    end

    context 'when porta 2: custom_attributes presente + identifier em branco desligava a checagem' do
      it 'nao altera o contato em PATCH /widget/contact' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, email: 'victim@corp.com',
                        custom_attributes: { plano: 'enterprise' } },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(victim.reload.custom_attributes).to eq({})
        expect_no_takeover
      end

      it 'nao altera o contato em PATCH /widget/contact/set_user' do
        patch '/api/v1/widget/contact/set_user',
              params: { website_token: web_widget.website_token, email: 'victim@corp.com',
                        custom_attributes: { plano: 'enterprise' } },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(victim.reload.custom_attributes).to eq({})
        expect_no_takeover
      end
    end

    # PORTA 5 — a refutacao do aceite literal do bloco ("com modo obrigatorio, as DUAS
    # chamadas nao alteram o contato").
    #
    # As portas 1 e 2 fecham quem chega SEM assinatura. Elas nao dizem nada sobre quem
    # chega COM assinatura valida — da PROPRIA identidade — carregando no mesmo corpo o
    # e-mail de outra pessoa. Esse pedido passa por `validate_hmac` legitimamente (a
    # assinatura confere sobre o `identifier` do atacante) e cai inteiro no
    # ContactIdentifyAction, que funde por e-mail quando o dono do e-mail nao tem
    # `identifier` proprio (`merge_contacts?` so barra identifier DIFERENTE; identifier em
    # branco na vitima nao barra nada — contact_identify_action.rb:110-123).
    #
    # A vitima aqui NAO tem identifier de proposito: e a forma real de contato criado por
    # pre-chat, pelo agente ou pela API de conta. Dar identifier a ela esconderia o
    # defeito — o teste passaria verde sem que portao nenhum existisse.
    #
    # O portao que impede isto (`refuse_merge_under_enforcement?`, bloco 4.16) ja existia,
    # mas ficava inerte aqui: `identify_contact` nao passava `identity_enforcement:`,
    # entao `strict_identity?` lia `nil` e devolvia false justamente no endpoint que este
    # bloco endureceu.
    context 'when porta 5: assinatura valida da propria identidade + e-mail de outra pessoa' do
      let!(:alvo) do
        create(:contact, account: account, name: 'Alvo', email: 'alvo@corp.com', phone_number: '+5511988887777')
      end
      let!(:alvo_inbox) { create(:contact_inbox, contact: alvo, inbox: web_widget.inbox) }
      let!(:alvo_conversa) do
        create(:conversation, account: account, inbox: web_widget.inbox, contact: alvo, contact_inbox: alvo_inbox)
      end

      # O atacante assina a PROPRIA identidade. A assinatura e legitima; o abuso esta no
      # campo de terceiro que viaja junto no mesmo corpo.
      let(:hash_do_atacante) do
        OpenSSL::HMAC.hexdigest('sha256', web_widget.hmac_token, 'atacante-identifier')
      end

      def identifica_com_email_alheio(rota)
        patch rota,
              params: { website_token: web_widget.website_token, identifier: 'atacante-identifier',
                        identifier_hash: hash_do_atacante, email: 'alvo@corp.com', name: 'Atacante' },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json
      end

      # A sessao continua no contato do atacante, o cadastro do alvo continua inteiro e o
      # identifier do atacante NAO foi carimbado nele.
      def expect_alvo_intacto
        expect(attacker_inbox.reload.contact_id).to eq(attacker.id)
        expect_cadastro_do_alvo_intacto
      end

      def expect_cadastro_do_alvo_intacto
        alvo_atual = alvo.reload
        expect(alvo_atual.identifier).to be_nil
        expect(alvo_atual.email).to eq('alvo@corp.com')
        expect(alvo_atual.contact_inboxes.pluck(:id)).to eq([alvo_inbox.id])
        expect(alvo_atual.conversations.pluck(:id)).to eq([alvo_conversa.id])
      end

      it 'nao funde em PATCH /widget/contact — e a requisicao NAO e recusada por 401' do
        identifica_com_email_alheio('/api/v1/widget/contact')

        # O 200 faz parte do aceite: quem barra e o portao de merge, nao o HMAC. Se isto
        # virasse 401, o teste estaria medindo a porta 1 de novo, nao a porta 5.
        expect(response).to have_http_status(:success)
        expect_alvo_intacto
      end

      it 'nao funde em PATCH /widget/contact/set_user — e a requisicao NAO e recusada por 401' do
        identifica_com_email_alheio('/api/v1/widget/contact/set_user')

        expect(response).to have_http_status(:success)
        expect_alvo_intacto
      end

      it 'nao reivindica o e-mail alheio para o contato do atacante' do
        identifica_com_email_alheio('/api/v1/widget/contact')

        expect(attacker.reload.email).to be_nil
      end

      # O atacante continua dono do que e dele: a assinatura vale para a identidade dele.
      # Sem esta assercao, "nao mudou nada" tambem passaria se a requisicao inteira fosse
      # descartada — e ai o portao estaria largo demais, nao correto.
      it 'grava a identidade PROPRIA do atacante, que e o que a assinatura prova' do
        identifica_com_email_alheio('/api/v1/widget/contact')

        expect(attacker.reload.identifier).to eq('atacante-identifier')
        expect(attacker.name).to eq('Atacante')
      end

      # `Contact#prepare_phone_number_attribute` normaliza pelo BrazilPhoneNormalizer (o 9o
      # digito entra na gravacao), entao o telefone GRAVADO pode nao ser o literal do
      # fixture. O ataque tem de carregar o que esta no banco: com um literal fora da forma
      # normalizada o `find_by` da action nao acha ninguem, nao existe fusao a recusar e
      # este exemplo passaria verde sem portao nenhum. Por isso o valor e lido de volta do
      # banco e a guarda abaixo confere que ele realmente casa com o alvo.
      it 'nao funde pelo telefone de outra pessoa' do
        telefone = alvo.reload.phone_number
        expect(account.contacts.find_by(phone_number: telefone)&.id).to eq(alvo.id)

        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identifier: 'atacante-identifier',
                        identifier_hash: hash_do_atacante, phone_number: telefone },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(attacker_inbox.reload.contact_id).to eq(attacker.id)
        expect(alvo.reload.phone_number).to eq(telefone)
        expect(attacker.reload.phone_number).to be_nil
      end

      # CONTROLE POSITIVO (anti-vacuo). "Nao fundiu" tambem passa quando a fusao nunca
      # teve como acontecer. Aqui a MESMA requisicao assinada, contra a MESMA forma de
      # vitima, mudando SO o estado de enforcement da inbox, PRECISA fundir — senao o que
      # barra o ataque acima e outra coisa qualquer, e nao o portao.
      context 'when a mesma requisicao chega numa inbox sem enforcement' do
        let(:web_widget) { create(:channel_widget, account: account, hmac_mandatory: false) }

        it 'funde — provando que o takeover existe e que e o portao que o barra' do
          identifica_com_email_alheio('/api/v1/widget/contact')

          expect(response).to have_http_status(:success)
          expect(attacker_inbox.reload.contact_id).to eq(alvo.id)
        end
      end

      # Nao-regressao sob obrigatorio: a regra e estreita de proposito — so morde quando o
      # campo pertence a OUTRO cadastro.
      it 'identidade assinada com e-mail que nao e de ninguem continua gravando' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identifier: 'atacante-identifier',
                        identifier_hash: hash_do_atacante, email: 'ninguem@corp.com' },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(attacker.reload.email).to eq('ninguem@corp.com')
      end
    end

    context 'when hmac obrigatorio: o que continua funcionando' do
      it 'aceita setCustomAttributes (sem campo de identidade) na sessao corrente' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, custom_attributes: { carrinho_valor: 4200 } },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(attacker.reload.custom_attributes).to eq({ 'carrinho_valor' => 4200 })
        expect_no_takeover
      end

      it 'aceita identidade quando o identifier_hash e valido' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, identifier: 'victim-identifier',
                        identifier_hash: OpenSSL::HMAC.hexdigest('sha256', web_widget.hmac_token, 'victim-identifier'),
                        name: 'Legit' },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(victim.reload.name).to eq('Legit')
      end
    end

    # Nao-regressao: quem NAO usa HMAC (hmac_mandatory=false, sem identifier_hash)
    # tem que continuar exatamente como hoje, merge por e-mail incluso.
    context 'when nao-regressao: inbox que nao usa HMAC' do
      let(:web_widget) { create(:channel_widget, account: account, hmac_mandatory: false) }

      it 'continua identificando por e-mail sem identifier_hash' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, email: 'victim@corp.com', name: 'Prechat' },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(attacker_inbox.reload.contact_id).to eq(victim.id)
      end

      it 'continua aceitando custom_attributes sem identifier' do
        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, custom_attributes: { carrinho_valor: 4200 } },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(attacker.reload.custom_attributes).to eq({ 'carrinho_valor' => 4200 })
      end

      it 'continua aceitando set_user sem identifier_hash' do
        patch '/api/v1/widget/contact/set_user',
              params: { website_token: web_widget.website_token, identifier: 'novo-id', name: 'Novo' },
              headers: { 'X-Auth-Token' => attacker_token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(attacker.reload.identifier).to eq('novo-id')
      end
    end
  end

  describe 'PATCH /api/v1/widget/contact/set_user' do
    let(:params) { { website_token: web_widget.website_token, identifier: 'test' } }
    let(:web_widget) { create(:channel_widget, account: account, hmac_mandatory: true) }
    let(:correct_identifier_hash) { OpenSSL::HMAC.hexdigest('sha256', web_widget.hmac_token, params[:identifier].to_s) }
    let(:incorrect_identifier_hash) { 'test' }

    context 'when the current contact identifier is different from param identifier' do
      before do
        contact.update(identifier: 'random')
      end

      it 'return a new contact for the provided identifier' do
        patch '/api/v1/widget/contact/set_user',
              params: params.merge(identifier_hash: correct_identifier_hash),
              headers: { 'X-Auth-Token' => token },
              as: :json

        body = response.parsed_body
        expect(body['id']).not_to eq(contact.id)
        expect(body['widget_auth_token']).not_to be_nil
        expect(Contact.find(body['id']).contact_inboxes.first.hmac_verified?).to be(true)
      end
    end

    context 'with mandatory hmac' do
      let(:identify_action) { double }

      before do
        allow(ContactIdentifyAction).to receive(:new).and_return(identify_action)
        allow(identify_action).to receive(:perform).and_return(contact)
      end

      it 'returns success when correct identifier hash is provided' do
        patch '/api/v1/widget/contact/set_user',
              params: params.merge(identifier_hash: correct_identifier_hash),
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:success)
      end

      it 'returns error when incorrect identifier hash is provided' do
        patch '/api/v1/widget/contact/set_user',
              params: params.merge(identifier_hash: incorrect_identifier_hash),
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns error when identifier hash is blank' do
        patch '/api/v1/widget/contact/set_user',
              params: params.merge(identifier_hash: ''),
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns error when identifier hash is not provided' do
        patch '/api/v1/widget/contact/set_user',
              params: params,
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/widget/destroy_custom_attributes' do
    let(:params) { { website_token: web_widget.website_token, identifier: 'test', custom_attributes: ['test'] } }

    context 'with invalid website token' do
      it 'returns unauthorized' do
        post '/api/v1/widget/destroy_custom_attributes', params: { website_token: '' }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with correct website token' do
      it 'calls destroy custom attributes' do
        post '/api/v1/widget/destroy_custom_attributes',
             params: params,
             headers: { 'X-Auth-Token' => token },
             as: :json
        expect(contact.reload.custom_attributes).to eq({})
      end
    end
  end
end
