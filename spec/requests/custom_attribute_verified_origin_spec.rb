require 'rails_helper'

# Bloco 4.17 — a flag `requires_verified_origin` precisa ser GRAVAVEL, LEGIVEL e, na API
# publica, o portao precisa morder.
#
# O que este arquivo mede e o que a auditoria refutou no bloco: o portao existia e recusava
# por chave, mas a unica forma de LIGAR a flag era `update_column` no console — o permit nao
# a aceitava, o jbuilder nao a devolvia. Portao correto sobre coluna que ninguem consegue
# escrever e portao que nunca fecha.
#
# E `Public::Api::V1::Inboxes::ContactsController#update` chamava a action sem dizer nada
# sobre a origem, caindo no default `verified_origin: true`: quem nao apresenta credencial
# nenhuma era tratado como verificado. Isso e fail-open, e e o pior dos dois — o outro
# deixa o portao inerte, este deixa o portao ABERTO para quem sabe que ele existe.
RSpec.describe 'requires_verified_origin: caminho de escrita e fail-open', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :administrator) }

  # ---------------------------------------------------------------------------------------
  # 1. O caminho de escrita pela API de conta (permit + jbuilder)
  # ---------------------------------------------------------------------------------------
  describe 'API de conta' do
    let(:payload) do
      {
        custom_attribute_definition: {
          attribute_display_name: 'CPF',
          attribute_key: 'cpf',
          attribute_model: 'contact_attribute',
          attribute_display_type: 'text',
          requires_verified_origin: true
        }
      }
    end

    it 'GRAVA a flag no create' do
      post "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
           headers: agente.create_new_auth_token, params: payload, as: :json

      expect(response).to have_http_status(:success)
      expect(CustomAttributeDefinition.last.requires_verified_origin).to be(true)
    end

    it 'DEVOLVE a flag no corpo do create' do
      post "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
           headers: agente.create_new_auth_token, params: payload, as: :json

      expect(response.parsed_body['requires_verified_origin']).to be(true)
    end

    context 'when ja existe uma definicao' do
      let!(:definicao) do
        create(:custom_attribute_definition, account: account, attribute_key: 'cpf',
                                             attribute_model: 'contact_attribute', attribute_display_type: 'text')
      end

      def patch_flag(valor)
        patch "/api/v1/accounts/#{account.id}/custom_attribute_definitions/#{definicao.id}",
              headers: agente.create_new_auth_token,
              params: { custom_attribute_definition: { requires_verified_origin: valor } }, as: :json
      end

      it 'LIGA a flag no update' do
        patch_flag(true)

        expect(response).to have_http_status(:success)
        expect(definicao.reload.requires_verified_origin).to be(true)
      end

      # Controle negativo do par: se o permit aceitasse a chave mas o modelo a ignorasse,
      # o teste de cima passaria por coincidencia em qualquer valor. Este exige que o
      # valor gravado ACOMPANHE o que foi mandado.
      it 'DESLIGA a flag no update' do
        definicao.update!(requires_verified_origin: true)

        patch_flag(false)

        expect(definicao.reload.requires_verified_origin).to be(false)
      end

      it 'DEVOLVE a flag no index' do
        definicao.update!(requires_verified_origin: true)

        get "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
            headers: agente.create_new_auth_token, params: { attribute_model: 'contact_attribute' }, as: :json

        expect(response.parsed_body.first).to have_key('requires_verified_origin')
        expect(response.parsed_body.first['requires_verified_origin']).to be(true)
      end

      it 'DEVOLVE a origem no index' do
        get "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
            headers: agente.create_new_auth_token, params: { attribute_model: 'contact_attribute' }, as: :json

        expect(response.parsed_body.first).to have_key('origin')
      end
    end

    # A origem tem de ser gravada nos DOIS lados para significar alguma coisa: o site ja
    # grava 'website' (AutoProvisionService). Sem o outro lado, `origin` responde "website
    # ou nao se sabe", e "nao se sabe" e a resposta de toda definicao criada pelo painel.
    it 'carimba origin=agent na definicao criada pelo painel' do
      post "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
           headers: agente.create_new_auth_token, params: payload, as: :json

      expect(CustomAttributeDefinition.last.origin).to eq(CustomAttributeDefinition::ORIGIN_AGENT)
    end

    # O agente e dono da definicao; o corpo da requisicao dele nao pode reivindicar
    # a origem do site e ganhar o selo do 1.17.
    it 'ignora origin vindo do corpo' do
      post "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
           headers: agente.create_new_auth_token,
           params: { custom_attribute_definition: payload[:custom_attribute_definition].merge(
             origin: CustomAttributeDefinition::ORIGIN_WEBSITE
           ) }, as: :json

      expect(CustomAttributeDefinition.last.origin).to eq(CustomAttributeDefinition::ORIGIN_AGENT)
      expect(CustomAttributeDefinition.last.auto_provisioned_from_website?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------------------
  # 2. Ponta a ponta: a flag ligada PELA TELA fecha o portao no widget
  # ---------------------------------------------------------------------------------------
  describe 'da API de conta ate o portao do widget' do
    let(:web_widget) { create(:channel_widget, account: account) }
    let(:inbox) { web_widget.inbox }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, hmac_verified: false) }
    let!(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                            custom_attributes: { 'cpf' => '111.111.111-11' })
    end
    let(:token) do
      Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
    end

    def cria_definicao(protegida:)
      post "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
           headers: agente.create_new_auth_token,
           params: { custom_attribute_definition: { attribute_display_name: 'CPF', attribute_key: 'cpf',
                                                    attribute_model: 'conversation_attribute',
                                                    attribute_display_type: 'text',
                                                    requires_verified_origin: protegida } }, as: :json
    end

    def escreve_pelo_widget
      post '/api/v1/widget/conversations/set_custom_attributes',
           params: { website_token: web_widget.website_token, custom_attributes: { cpf: '999.999.999-99' } },
           headers: { 'X-Auth-Token' => token }, as: :json
    end

    it 'com a flag LIGADA pela API, a escrita sem assinatura nao altera o valor' do
      cria_definicao(protegida: true)

      escreve_pelo_widget

      expect(conversation.reload.custom_attributes['cpf']).to eq('111.111.111-11')
    end

    # Controle positivo. Sem ele o teste de cima passa tambem num mundo onde
    # `set_custom_attributes` esta quebrado e nao grava nada nunca.
    it 'com a flag DESLIGADA pela API, a mesma escrita passa' do
      cria_definicao(protegida: false)

      escreve_pelo_widget

      expect(conversation.reload.custom_attributes['cpf']).to eq('999.999.999-99')
    end
  end

  # ---------------------------------------------------------------------------------------
  # 3. O fail-open da API publica
  # ---------------------------------------------------------------------------------------
  describe 'API publica de contatos' do
    let(:api_channel) { create(:channel_api, account: account) }
    let(:inbox) { api_channel.inbox }
    let(:contact) do
      create(:contact, account: account, custom_attributes: { 'cpf' => '111.111.111-11', 'plano' => 'free' })
    end
    let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, hmac_verified: false) }

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'cpf',
                                           attribute_model: 'contact_attribute', attribute_display_type: 'text',
                                           requires_verified_origin: true)
    end

    def escreve(attrs)
      patch "/public/api/v1/inboxes/#{api_channel.identifier}/contacts/#{contact_inbox.source_id}",
            params: { custom_attributes: attrs }, as: :json
    end

    it 'sem credencial, NAO altera o atributo protegido' do
      escreve({ cpf: '999.999.999-99' })

      expect(response).to have_http_status(:success)
      expect(contact.reload.custom_attributes['cpf']).to eq('111.111.111-11')
    end

    it 'sem credencial, grava as chaves nao protegidas do mesmo payload' do
      escreve({ cpf: '999.999.999-99', plano: 'premium' })

      atributos = contact.reload.custom_attributes
      expect(atributos['plano']).to eq('premium')
      expect(atributos['cpf']).to eq('111.111.111-11')
    end

    it 'registra a tentativa' do
      allow(Rails.logger).to receive(:warn)

      escreve({ cpf: '999.999.999-99' })

      expect(Rails.logger).to have_received(:warn)
        .with(/escrita recusada por origem nao verificada account_id=#{account.id} .*chaves=cpf/)
    end

    # Controle positivo: sessao com identidade conferida escreve o protegido.
    it 'com a sessao verificada, o valor MUDA' do
      contact_inbox.update!(hmac_verified: true)

      escreve({ cpf: '999.999.999-99' })

      expect(contact.reload.custom_attributes['cpf']).to eq('999.999.999-99')
    end
  end

  # ---------------------------------------------------------------------------------------
  # 4. O default da action
  # ---------------------------------------------------------------------------------------
  #
  # Este e o teste que ACUSA o default aberto, sem passar por controller nenhum. Enquanto o
  # default for `true`, todo chamador futuro que esquecer o argumento herda o fail-open em
  # silencio — foi exatamente assim que a API publica nasceu furada.
  describe 'ContactIdentifyAction sem verified_origin' do
    let(:contact) { create(:contact, account: account, custom_attributes: { 'cpf' => '111.111.111-11' }) }

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'cpf',
                                           attribute_model: 'contact_attribute', attribute_display_type: 'text',
                                           requires_verified_origin: true)
    end

    it 'trata a origem como NAO verificada' do
      ContactIdentifyAction.new(contact: contact, params: { custom_attributes: { cpf: '999.999.999-99' } }).perform

      expect(contact.reload.custom_attributes['cpf']).to eq('111.111.111-11')
    end
  end
end
