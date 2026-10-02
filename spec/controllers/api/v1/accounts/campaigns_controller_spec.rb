require 'rails_helper'

RSpec.describe 'Campaigns API', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/campaigns' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/campaigns"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }
      let(:inbox) { create(:inbox, account: account) }
      let!(:campaign) { create(:campaign, account: account, inbox: inbox, trigger_rules: { url: 'https://test.com' }) }

      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/campaigns",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns all campaigns to administrators' do
        get "/api/v1/accounts/#{account.id}/campaigns",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.first[:id]).to eq(campaign.display_id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'shows the campaign for administrators' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:id]).to eq(campaign.display_id)
      end
    end
  end

  # O preview existe para que o operador VEJA a mensagem antes de ela sair, e o valor dele
  # depende inteiramente de renderizar IGUAL ao envio: preview que diverge do que o
  # `RecipientDispatchService` monta e pior que preview nenhum, porque e nele que o operador
  # vai confiar. Estes exemplos prendem as tres garantias que sustentam isso.
  describe 'GET /api/v1/accounts/{account.id}/campaigns/:id/stats' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                                message_templates: [{
                                  'name' => 'abertura', 'status' => 'APPROVED', 'language' => 'pt_BR',
                                  'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, aqui e {{2}}.' }]
                                }])
    end
    # A factory do canal ja cria a inbox no after(:create) — criar outra aqui geraria duas.
    let(:inbox) { channel.inbox }
    let(:campaign) do
      create(:campaign, account: account, inbox: inbox, template_name: 'abertura', template_language: 'pt_BR',
                        dispatch_config: { 'default_params' => { '2' => 'Kettlen' } })
    end

    def pendente(params, nome: 'Maria')
      CampaignRecipient.create!(campaign: campaign, account: account, name: nome,
                                phone_number: '5566999998888', template_params: params, status: :pending)
    end

    def preview
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/stats",
          headers: administrator.create_new_auth_token, as: :json
      JSON.parse(response.body, symbolize_names: true)[:dispatch_preview]
    end

    it 'renders the approved body with the next pending recipient params' do
      pendente({ '1' => 'Maria' })

      expect(preview[:body]).to eq('Oi Maria, aqui e Kettlen.')
      expect(preview[:contact_name]).to eq('Maria')
      expect(preview[:missing]).to be_empty
    end

    # O defeito real: 124 pessoas receberam "Oi , sou a Kettlen" porque o parametro chegou
    # vazio, e o status nao acusa nada — a Meta aceita. Aqui ele fica visivel ANTES do envio.
    it 'reports the variable the template requires and the params leave empty' do
      pendente({})

      expect(preview[:missing]).to include('1')
    end

    # Sem template sincronizado a tela diz que nao consegue mostrar, em vez de inventar um
    # corpo: degradar com honestidade vale para o preview tambem.
    it 'returns a nil body when the template is not synced on the channel' do
      pendente({ '1' => 'Maria' })
      campaign.update!(template_name: 'inexistente')

      expect(preview[:body]).to be_nil
      expect(preview[:template_name]).to eq('inexistente')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/campaigns' do
    let(:inbox) { create(:inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a new campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end

      it 'creates a new ongoing campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message', trigger_rules: { url: 'https://test.com' } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end

      it 'throws error when invalid url provided for ongoing campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message', trigger_rules: { url: 'javascript' } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'creates a new oneoff campaign' do
        twilio_sms = create(:channel_twilio_sms, account: account)
        twilio_inbox = create(:inbox, channel: twilio_sms, account: account)
        label1 = create(:label, account: account)
        label2 = create(:label, account: account)
        scheduled_at = 2.days.from_now

        post "/api/v1/accounts/#{account.id}/campaigns",
             params: {
               inbox_id: twilio_inbox.id, title: 'test', message: 'test message',
               scheduled_at: scheduled_at,
               audience: [{ type: 'Label', id: label1.id }, { type: 'Label', id: label2.id }]
             },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        response_data = JSON.parse(response.body, symbolize_names: true)
        expect(response_data[:campaign_type]).to eq('one_off')
        expect(response_data[:scheduled_at].present?).to be true
        expect(response_data[:scheduled_at]).to eq(scheduled_at.to_i)
        expect(response_data[:audience].pluck(:id)).to include(label1.id, label2.id)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:inbox) { create(:inbox, account: account) }
    let!(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates the campaign' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:inbox) { create(:inbox, account: account) }
    let!(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'return unauthorized if agent' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'delete campaign if admin' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Campaign.exists?(campaign.display_id)).to be false
      end
    end
  end

  # Fatia 1 de campanhas (CHAT-167): a campanha criada pela TELA tem de disparar sem console.
  describe 'campanha WhatsApp criada pela tela' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:team) { create(:team, account: account) }
    # Canal montado a mão: a trait :whatsapp do factory cria 360dialog e bate na rede.
    let(:whatsapp_inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                sync_templates: false, validate_provider_config: false).inbox
    end
    # Exatamente o que o WhatsAppCampaignForm.vue envia: template só em `template_params`,
    # sem `template_name`, sem `audience` (quem recebe vem da lista carregada no detalhe).
    let(:form_payload) do
      {
        title: 'Aniversário', message: 'Olá {{1}}', inbox_id: whatsapp_inbox.id,
        template_params: { name: 'aniversario_v2', namespace: '', category: 'MARKETING',
                           language: 'pt_BR', processed_params: {} }
      }
    end

    def create_from_form(payload = form_payload)
      post "/api/v1/accounts/#{account.id}/campaigns",
           params: payload, headers: administrator.create_new_auth_token, as: :json
      Campaign.find_by!(account_id: account.id, display_id: response.parsed_body['id'])
    end

    def start(campaign)
      post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/start",
           headers: administrator.create_new_auth_token, as: :json
    end

    it 'aceita a campanha sem etiqueta de público e grava o template do disparo' do
      campaign = create_from_form

      expect(response).to have_http_status(:success)
      expect(campaign.audience).to be_blank
      expect(campaign.template_name).to eq('aniversario_v2')
      expect(campaign.template_language).to eq('pt_BR')
      expect(campaign).to be_whatsapp_blast
    end

    it 'o start aceita a campanha criada pela tela depois da lista e do time' do
      campaign = create_from_form
      campaign.update!(target_team_id: team.id)
      CampaignRecipient.create!(campaign: campaign, account: account, phone_number: '+5566992927211')

      start(campaign)

      expect(response).to have_http_status(:success)
      expect(campaign.reload).to be_dispatch_running
    end

    it 'o start recusa campanha sem time, porque a resposta do lead cairia sem dono' do
      campaign = create_from_form
      CampaignRecipient.create!(campaign: campaign, account: account, phone_number: '+5566992927211')

      start(campaign)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(campaign.reload).to be_dispatch_draft
    end

    it 'nasce agendada quando a tela manda horário, e em rascunho quando não manda' do
      agendada = create_from_form(form_payload.merge(scheduled_at: 1.day.from_now.iso8601))
      rascunho = create_from_form

      expect(agendada).to be_dispatch_scheduled
      expect(rascunho).to be_dispatch_draft
    end

    it 'não sobrescreve template_name informado explicitamente' do
      campaign = create_from_form(form_payload.merge(template_name: 'outro_template', template_language: 'en'))

      expect(campaign.template_name).to eq('outro_template')
      expect(campaign.template_language).to eq('en')
    end
  end
end
