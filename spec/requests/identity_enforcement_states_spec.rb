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

    it 'recusa mesmo com desativado gravado no jsonb' do
      web_widget.update!(hmac_mandatory: true)
      inbox.update!(identity_enforcement: 'desativado')

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
end
