require 'rails_helper'

# Bloco 4.05 — o CONTRATO do payload que a tela de gatilhos consome.
#
# O compositor do teaser (`TeaserComposer.vue`) nao le a resposta crua: ele le o
# getter `campaigns/getLiveChatCampaigns`, que filtra por
# `campaign_type === 'ongoing'` E `inbox.channel_type === 'Channel::WebWidget'`.
# Uma campanha sem esses dois campos some do getter em silencio, e a tela mostra
# "esta caixa ainda nao tem campanha" com a campanha existindo no banco.
#
# Este spec existe porque o spec do front dubla a camada HTTP. O duble so vale se
# tiver a forma REAL — entao a forma e fixada aqui, contra o serializador de
# verdade, e o fixture de `TeaserComposer.storeReal.spec.js` e copia deste corpo.
RSpec.describe 'Contrato do payload de campanhas para a tela de gatilhos', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:web_inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }

  describe 'GET /api/v1/accounts/{account.id}/campaigns' do
    let!(:live_chat_campaign) do
      create(:campaign, account: account, inbox: web_inbox, title: 'Convite da pagina de planos',
                        message: 'Posso ajudar a escolher o plano?', trigger_rules: { url: 'https://simplex.test/planos' })
    end

    let(:body) do
      get "/api/v1/accounts/#{account.id}/campaigns", headers: administrator.create_new_auth_token, as: :json
      response.parsed_body
    end

    let(:payload) { body.find { |item| item['title'] == 'Convite da pagina de planos' } }

    it 'traz os quatro campos de que o getter de chat ao vivo depende' do
      expect(payload).to include(
        'id' => live_chat_campaign.display_id,
        'title' => 'Convite da pagina de planos',
        'message' => 'Posso ajudar a escolher o plano?',
        'campaign_type' => 'ongoing',
        'enabled' => true
      )
      expect(payload['inbox']).to include('id' => web_inbox.id, 'channel_type' => 'Channel::WebWidget')
    end

    # O `id` do payload e o `display_id`, e e ele que a tela devolve no PATCH
    # (`campaigns/update` -> `CampaignsAPI.update(id, ...)` -> `find_by!(display_id:)`).
    # Se o serializador passasse a mandar o id da tabela, o PATCH da tela erraria
    # de campanha sem nenhum erro visivel.
    it 'usa o display_id como `id`, que e a chave que o PATCH da tela consome' do
      expect(payload['id']).to eq(live_chat_campaign.display_id)
    end

    # O aceite do bloco, atravessando a junta: o `id` que a tela guardou do GET
    # volta no PATCH e cai na campanha VINCULADA. Nenhum dos dois lados sozinho
    # prova isto — o front so sabe qual numero mandou, o backend so sabe qual
    # numero recebeu.
    it 'aceita de volta o `id` do GET e edita a campanha vinculada — sem criar outra' do
      headers = administrator.create_new_auth_token
      id_que_a_tela_guardou = payload['id']

      # Verbo e corpo iguais aos do cliente: `CampaignsAPI.update` faz
      # `axios.patch(url, { title, message })`, sem envelope — quem envelopa e o
      # `wrap_parameters` do Rails.
      expect do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{id_que_a_tela_guardou}",
              params: { title: 'Convite da pagina de planos', message: 'Quer ajuda para comparar os planos?' },
              headers: headers, as: :json
      end.not_to change(account.campaigns, :count)

      expect(response).to have_http_status(:success)
      expect(live_chat_campaign.reload.message).to eq('Quer ajuda para comparar os planos?')
    end

    # A campanha de disparo vem na MESMA resposta — o endpoint nao filtra — e e
    # `campaign_type`/`channel_type` que a tiram da tela de gatilhos. E o mesmo
    # par de campos que o fixture do front carrega, pelo mesmo motivo.
    it 'marca a campanha de disparo como one_off, que e o que a tira da tela de gatilhos' do
      # Criar o canal WhatsApp registra o webhook no 360dialog; aqui so interessa a
      # forma do payload, entao a ida a rede fica dublada como no resto da suite.
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook').to_return(status: 200, body: '', headers: {})
      stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates').to_return(status: 200, body: '', headers: {})
      create(:campaign, :whatsapp, account: account, title: 'Disparo de agosto', scheduled_at: 2.days.from_now,
                                   audience: [{ type: 'Label', id: 1 }])

      disparo = body.find { |item| item['title'] == 'Disparo de agosto' }
      expect(disparo['campaign_type']).to eq('one_off')
      expect(disparo['inbox']['channel_type']).to eq('Channel::Whatsapp')
    end
  end
end
