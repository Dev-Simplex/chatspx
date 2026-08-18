require 'rails_helper'

# Aceite do bloco 1.18: "as chaves aparecem no painel de uma conversa que as tenha".
# O painel do agente é feito de duas chamadas — as DEFINIÇÕES (que dão nome e tipo) e a CONVERSA
# (que dá o valor). Sem a definição, o valor está no banco e o painel não o mostra: é o mesmo
# efeito prático de não existir. Por isso o teste bate nas duas.
RSpec.describe 'Definições de origem no painel (1.18)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, custom_attributes: {
             'last_utm_source' => 'google',
             'last_utm_medium' => 'cpc',
             'last_utm_campaign' => 'institucional_agosto',
             'last_gclid' => 'Cj0KCQ-exemplo',
             'last_origin_kind' => 'busca_paga'
           })
  end

  before { create(:inbox_member, user: admin, inbox: inbox) }

  def definicoes_do_painel
    get "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
        params: { attribute_model: 'conversation_attribute' },
        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body
  end

  context 'when a conta ainda não foi semeada (o defeito que o bloco fecha)' do
    it 'a conversa tem os valores no banco e o painel não conhece nenhuma das chaves' do
      expect(conversation.reload.custom_attributes['last_utm_source']).to eq('google')

      chaves = definicoes_do_painel.pluck('attribute_key')

      expect(chaves & Tracking::OriginAttributes.conversation_keys).to eq([])
    end
  end

  context 'when o seed já rodou' do
    before { Tracking::OriginDefinitionsSeeder.new(account).perform }

    it 'o painel conhece as 15 chaves de conversa, com nome e tipo' do
      definicoes = definicoes_do_painel
      por_chave = definicoes.index_by { |d| d['attribute_key'] }

      expect(por_chave.keys & Tracking::OriginAttributes.conversation_keys)
        .to match_array(Tracking::OriginAttributes.conversation_keys)
      expect(por_chave['last_utm_source']['attribute_display_name']).to eq('Origem da campanha (última)')
      expect(por_chave['last_utm_source']['attribute_display_type']).to eq('text')
      expect(por_chave['last_origin_kind']['attribute_display_type']).to eq('list')
      expect(por_chave['last_origin_kind']['attribute_values']).to include('ia_generativa', 'nao_disponivel')
      expect(por_chave['last_origin_kind']['attribute_values']).not_to include('direta')
    end

    it 'a conversa devolve os valores dessas chaves na mesma resposta que o painel usa' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      atributos = response.parsed_body['custom_attributes']

      expect(atributos['last_utm_source']).to eq('google')
      expect(atributos['last_utm_medium']).to eq('cpc')
      expect(atributos['last_utm_campaign']).to eq('institucional_agosto')
      expect(atributos['last_gclid']).to eq('Cj0KCQ-exemplo')
      expect(atributos['last_origin_kind']).to eq('busca_paga')
    end

    it 'as chaves de origem viram filtráveis na lista de conversas' do
      alvo = conversation
      outra = create(:conversation, account: account, inbox: inbox, custom_attributes: { 'last_utm_source' => 'meta' })

      post "/api/v1/accounts/#{account.id}/conversations/filter",
           params: {
             payload: [{
               attribute_key: 'last_utm_source', filter_operator: 'equal_to',
               values: ['google'], query_operator: nil, custom_attribute_type: 'conversation_attribute'
             }]
           },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      # A API de conversas expõe `display_id` no campo `id` do payload.
      ids = response.parsed_body['payload'].pluck('id')

      expect(ids).to eq([alvo.display_id])
      expect(ids).not_to include(outra.display_id)
    end

    it 'rodar o seed de novo não muda o que o painel mostra' do
      antes = definicoes_do_painel

      Tracking::OriginDefinitionsSeeder.new(account).perform

      expect(definicoes_do_painel.pluck('attribute_key')).to match_array(antes.pluck('attribute_key'))
    end
  end
end
