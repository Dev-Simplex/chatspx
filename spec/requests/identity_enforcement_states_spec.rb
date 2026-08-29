require 'rails_helper'

# Bloco 4.15 — o aceite: ligar `observado` numa inbox com trafego produz a lista de
# identificacoes nao verificadas SEM quebrar nenhuma sessao.
#
# O par de asserções que importa em cada exemplo e sempre o mesmo: o status da resposta
# (a sessao quebrou ou nao) e o que ficou no banco (a contabilidade sobreviveu ou nao).
RSpec.describe 'enforcement de identidade — os tres estados', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  # A vitima: contato ja identificado nesta conta. E o alvo do merge que o 1.11 mediu.
  let!(:victim) { create(:contact, account: account, email: 'cliente@corp.com') }

  # A sessao anonima de quem esta chamando.
  let(:visitor) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: visitor, inbox: inbox, hmac_verified: false) }
  let(:token) { Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token }

  def bind_identity_without_signature(email: 'cliente@corp.com')
    patch '/api/v1/widget/contact',
          params: { website_token: web_widget.website_token, email: email },
          headers: { 'X-Auth-Token' => token },
          as: :json
  end

  describe 'desativado — o comportamento de hoje, intacto' do
    before { inbox.update!(identity_enforcement: 'desativado') }

    it 'aceita a identificacao sem assinatura' do
      bind_identity_without_signature

      expect(response).to have_http_status(:success)
      expect(contact_inbox.reload.hmac_verified).to be(false)
    end
  end

  describe 'observado — nao quebra sessao e deixa a conta para tras' do
    before { inbox.update!(identity_enforcement: 'observado') }

    it 'aceita a identificacao sem assinatura, exatamente como desativado' do
      bind_identity_without_signature

      expect(response).to have_http_status(:success)
    end

    # A armadilha que este exemplo existe para travar: sob `observado`,
    # `should_verify_hmac?` fica verdadeiro, e a linha que marca a sessao como
    # verificada teria marcado uma sessao SEM assinatura conferida — apagando o unico
    # sinal de que o relatorio depende.
    it 'nao marca a sessao como verificada — o sinal do relatorio sobrevive' do
      bind_identity_without_signature

      expect(contact_inbox.reload.hmac_verified).to be(false)
    end

    it 'registra a observacao no log, com a inbox e os campos de identidade' do
      allow(Rails.logger).to receive(:info)

      bind_identity_without_signature

      expect(Rails.logger).to have_received(:info)
        .with(/\[identity_enforcement\] observado inbox_id=#{inbox.id} .*campos=email/)
    end

    # `set_user` e o unico caminho que ESCREVE hmac_verified, e por isso e o unico onde a
    # armadilha existia de verdade. Os dois exemplos abaixo sao o par que a fecha.
    describe 'set_user, que e quem escreve hmac_verified' do
      def set_user(extra = {})
        patch '/api/v1/widget/contact/set_user',
              params: { website_token: web_widget.website_token }.merge(extra),
              headers: { 'X-Auth-Token' => token },
              as: :json
      end

      it 'NAO marca verificada quando a identidade chegou sem assinatura' do
        set_user(identifier: 'cliente-42')

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.hmac_verified).to be(false)
      end

      it 'marca verificada quando a assinatura e valida' do
        identifier = 'cliente-42'
        set_user(identifier: identifier,
                 identifier_hash: OpenSSL::HMAC.hexdigest('sha256', web_widget.hmac_token, identifier))

        expect(response).to have_http_status(:success)
        expect(contact_inbox.reload.hmac_verified).to be(true)
      end
    end
  end

  describe 'obrigatorio — recusa' do
    before { inbox.update!(identity_enforcement: 'obrigatorio') }

    it 'recusa a identificacao sem assinatura' do
      bind_identity_without_signature

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('HMAC failed: Invalid Identifier Hash Provided')
    end

    it 'nao move a sessao para o contato da vitima' do
      antes = contact_inbox.contact_id

      bind_identity_without_signature

      expect(contact_inbox.reload.contact_id).to eq(antes)
      expect(victim.reload.contact_inboxes).to be_empty
    end
  end

  # `hmac_mandatory` e a autoridade que a frota ja usa. Ele nao muda de comportamento.
  describe 'hmac_mandatory continua sendo o piso' do
    it 'recusa mesmo sem nada gravado no jsonb' do
      web_widget.update!(hmac_mandatory: true)

      bind_identity_without_signature

      expect(response).to have_http_status(:unauthorized)
    end

    # A ordem — gravar `desativado` e SO ENTAO ligar o `hmac_mandatory` — e a de uma inbox
    # de cliente que ja tinha o estado configurado quando o HMAC obrigatorio entrou. Ela
    # tambem e a unica pela qual esse valor ainda consegue existir: escrever `desativado`
    # com o canal ja mandatory passou a ser recusado (bloco mais abaixo neste arquivo).
    it 'recusa mesmo com desativado gravado no jsonb' do
      inbox.update!(identity_enforcement: 'desativado')
      web_widget.update!(hmac_mandatory: true)

      bind_identity_without_signature

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # A promessa do 1.11 que nao pode regredir: o que NAO e identidade segue funcionando
  # em qualquer estado, porque nada disso reamarra a sessao a outro contato.
  describe 'o que nao e identidade nao e afetado por nenhum estado' do
    %w[desativado observado obrigatorio].each do |state|
      it "aceita setCustomAttributes sob #{state}" do
        inbox.update!(identity_enforcement: state)

        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, custom_attributes: { carrinho_valor: 4200 } },
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(visitor.reload.custom_attributes).to include('carrinho_valor' => 4200)
      end

      it "aceita prechat anonimo com so o nome sob #{state}" do
        inbox.update!(identity_enforcement: state)

        patch '/api/v1/widget/contact',
              params: { website_token: web_widget.website_token, name: 'Visitante' },
              headers: { 'X-Auth-Token' => token },
              as: :json

        expect(response).to have_http_status(:success)
        expect(visitor.reload.name).to eq('Visitante')
      end
    end
  end

  # Sem isto o estado do meio nao existiria na pratica: `additional_attributes` tem lista
  # branca por chave, e chave fora dela e descartada em silencio pelo strong parameters.
  describe 'ligar o estado pela API da inbox' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'o administrador consegue ligar observado' do
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { additional_attributes: { identity_enforcement: 'observado' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.resolved_identity_enforcement).to eq('observado')
      expect(response.parsed_body['identity_enforcement']).to eq('observado')
    end

    it 'ligar o enforcement nao apaga a configuracao de widget que ja estava no jsonb' do
      inbox.update!(widget_profile: 'marketing')

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { additional_attributes: { identity_enforcement: 'observado' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(inbox.reload.widget_profile).to eq('marketing')
      expect(inbox.identity_enforcement).to eq('observado')
    end

    it 'recusa estado inexistente com erro por campo' do
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { additional_attributes: { identity_enforcement: 'meio_obrigatorio' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(inbox.reload.resolved_identity_enforcement).to eq('desativado')
    end

    # A marca de inicio da observacao decide o corte entre "medido" e "historico". Quem
    # pudesse gravar a marca poderia mover o corte e fazer o numero mentir.
    it 'NAO deixa forjar a marca de inicio da observacao pela API' do
      forjada = 5.years.ago.iso8601

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { additional_attributes: { identity_enforcement: 'observado',
                                               identity_enforcement_observed_since: forjada } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.identity_enforcement_observed_since).not_to eq(forjada)
      expect(inbox.identity_enforcement_observed_since_time).to be_within(30.seconds).of(Time.zone.now)
    end
  end

  # §12 do ESTADO-BLOCOS-DEFINITIVO, item 7: "se for teto, a API precisa parar de devolver
  # 200 para uma escrita que sera ignorada".
  #
  # A precedencia em si continua ESCALADA — quem decide se `hmac_mandatory` e piso ou teto
  # e o dono. O que estes exemplos travam e o unico lado da questao que nao depende da
  # decisao: em nenhuma das duas leituras e aceitavel gravar `observado`, responder 200 e
  # devolver `obrigatorio` na leitura seguinte. Sob "teto" a escrita e mentira; sob "piso"
  # a LEITURA e que esta errada — e nos dois casos o 200 de hoje esconde qual dos dois e.
  describe 'a API para de aceitar em silencio a escrita que sera ignorada' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    def ligar_estado(state)
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { additional_attributes: { identity_enforcement: state } },
            headers: admin.create_new_auth_token,
            as: :json
    end

    describe 'quando o canal exige assinatura (hmac_mandatory)' do
      before { web_widget.update!(hmac_mandatory: true) }

      it 'recusa observado com 422 em vez de gravar e ignorar' do
        ligar_estado('observado')

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'nao deixa nada gravado no jsonb depois da recusa' do
        ligar_estado('observado')

        expect(inbox.reload.identity_enforcement).to be_nil
      end

      it 'aceita obrigatorio, que e o que a inbox ja faz' do
        ligar_estado('obrigatorio')

        expect(response).to have_http_status(:success)
        expect(inbox.reload.identity_enforcement).to eq('obrigatorio')
      end
    end

    # O espelho: sem `hmac_mandatory` a mesma chamada continua passando. Sem esta metade,
    # a guarda acima passaria tambem se a escrita tivesse sido recusada para todo mundo.
    it 'continua aceitando observado na inbox sem hmac_mandatory' do
      ligar_estado('observado')

      expect(response).to have_http_status(:success)
      expect(inbox.reload.identity_enforcement).to eq('observado')
    end
  end

  # A guarda acima e uma peca de UM LADO SO da junta enquanto ela le o valor VELHO do
  # canal. `inboxes_controller#update` roda `@inbox.update!` ANTES de `update_channel`, na
  # mesma transacao: no instante em que a validacao pergunta `channel.hmac_mandatory`, o
  # canal ainda esta como estava antes da requisicao. Uma unica chamada com os dois lados
  # no mesmo corpo passa por baixo dela e reproduz exatamente o 200 mudo que a guarda diz
  # ter encerrado — pelo mesmo endpoint que ela protege.
  #
  # Os dois exemplos abaixo sao o mesmo defeito visto pelos dois lados, e por isso nenhum
  # deles pode faltar: um recusa blindar so a ordem que o teste enxerga, o outro recusa
  # "passou a barrar todo mundo" como conserto. O que a validacao tem de ler e o valor que
  # VAI VIGORAR ao fim da transacao, nao o que estava la quando ela comecou.
  describe 'a guarda nao pode ser contornada numa unica requisicao' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    def patch_composto(hmac:, state:)
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { channel: { hmac_mandatory: hmac },
                      additional_attributes: { identity_enforcement: state } },
            headers: admin.create_new_auth_token,
            as: :json
    end

    describe 'ligar hmac_mandatory e observado no MESMO corpo' do
      # A inbox comeca sem exigir assinatura — e o estado em que a guarda de hoje deixa
      # passar, porque e o valor que ela le.
      before { web_widget.update!(hmac_mandatory: false) }

      it 'recusa com 422 em vez de responder 200 para uma escrita que ja nasce ignorada' do
        patch_composto(hmac: true, state: 'observado')

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'nao deixa observado gravado no jsonb' do
        patch_composto(hmac: true, state: 'observado')

        expect(inbox.reload.identity_enforcement).to be_nil
      end

      # O sintoma exato do veredito: gravado `observado`, lido `obrigatorio`. Enquanto os
      # dois divergirem, quem apertou o botao vai abrir um relatorio de um estado que
      # nunca entrou em vigor.
      it 'nao deixa o gravado divergir do que vigora' do
        patch_composto(hmac: true, state: 'observado')

        inbox.reload
        expect(inbox.identity_enforcement.to_s).to eq(inbox.resolved_identity_enforcement) if inbox.identity_enforcement.present?
      end

      # A recusa e da transacao inteira: o canal nao pode ficar endurecido por uma
      # requisicao que foi respondida com 422.
      it 'nao endurece o canal numa requisicao recusada' do
        patch_composto(hmac: true, state: 'observado')

        expect(web_widget.reload.hmac_mandatory).to be(false)
      end

      it 'aceita o par coerente — hmac_mandatory com obrigatorio' do
        patch_composto(hmac: true, state: 'obrigatorio')

        expect(response).to have_http_status(:success)
        expect(inbox.reload.identity_enforcement).to eq('obrigatorio')
        expect(web_widget.reload.hmac_mandatory).to be(true)
      end
    end

    # O outro lado da junta, e o que separa "leu o valor certo" de "passou a recusar
    # sempre": DESLIGAR hmac_mandatory e pedir observado no mesmo corpo e um pedido
    # coerente — ao fim da transacao o canal nao exige mais assinatura e `observado` e
    # exatamente o que vai vigorar. Lendo o valor velho, a guarda recusa este caso com 422.
    describe 'desligar hmac_mandatory e pedir observado no MESMO corpo' do
      before { web_widget.update!(hmac_mandatory: true) }

      it 'aceita, porque ao fim da transacao o canal nao exige mais assinatura' do
        patch_composto(hmac: false, state: 'observado')

        expect(response).to have_http_status(:success)
      end

      it 'deixa observado vigorando de fato' do
        patch_composto(hmac: false, state: 'observado')

        expect(inbox.reload.resolved_identity_enforcement).to eq('observado')
        expect(web_widget.reload.hmac_mandatory).to be(false)
      end
    end
  end
end
