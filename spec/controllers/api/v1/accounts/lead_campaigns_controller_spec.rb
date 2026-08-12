require 'rails_helper'

RSpec.describe 'Lead Campaigns API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account, name: 'Atendente virtual') }
  let(:url) { "/api/v1/accounts/#{account.id}/lead_campaigns" }

  # Ids de campanha são opacos por natureza (vêm da plataforma de anúncios).
  let(:campanha_com_override) { '900000000000000001' }
  let(:campanha_sem_override) { '900000000000000002' }

  def criar_hook(overrides: {}, allowlist: nil)
    settings = {
      'page_id' => '1234567890',
      'page_name' => 'Página de teste',
      'verify_token' => 'verify',
      'app_secret' => 'secret',
      'page_access_token' => 'token',
      'target_inbox_id' => inbox.id,
      'whatsapp_template_name' => 'abertura_padrao',
      'assign_team_id' => team.id,
      'assign_agent_bot_id' => agent_bot.id,
      'campaign_overrides' => overrides
    }
    settings['allowed_campaign_ids'] = allowlist unless allowlist.nil?
    create(:integrations_hook, account: account, app_id: 'meta_lead_ads', settings: settings)
  end

  # Reproduz o que a engine de captação grava: origem em custom_attributes na conversa,
  # o par (id, nome) da campanha no contato, e o opener com o nome do template enviado.
  def criar_lead(nome_campanha:, campaign_id:, template:, tipo: 'Lead novo', origem: 'Facebook')
    contato = create(:contact, account: account,
                               additional_attributes: { 'source' => 'meta_lead_ads',
                                                        'campaign_id' => campaign_id,
                                                        'campaign_name' => nome_campanha })
    conversa = create(:conversation, account: account, inbox: inbox, contact: contato,
                                     additional_attributes: { 'source' => 'meta_lead_ads',
                                                              'lead' => { 'campaign_name' => nome_campanha } },
                                     custom_attributes: { 'meta_campanha' => nome_campanha,
                                                          'meta_tipo' => tipo, 'meta_origem' => origem })
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :outgoing,
                     additional_attributes: { 'template_params' => { 'name' => template } })
    conversa
  end

  def corpo
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/{account.id}/lead_campaigns' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get url

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the account has no lead intake hook' do
      it 'reports the screen as unavailable' do
        get url, headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(corpo[:habilitado]).to be(false)
        expect(corpo[:campanhas]).to eq([])
      end
    end

    context 'when an administrator lists the campaigns' do
      before do
        criar_hook(overrides: { campanha_com_override => { 'whatsapp_template_name' => 'abertura_custom',
                                                           'lead_tipo' => 'remarketing' } })
        criar_lead(nome_campanha: 'Campanha A', campaign_id: campanha_com_override, template: 'abertura_custom')
        criar_lead(nome_campanha: 'Campanha A', campaign_id: campanha_com_override, template: 'abertura_padrao')
        criar_lead(nome_campanha: 'Campanha B', campaign_id: campanha_sem_override, template: 'abertura_padrao')
      end

      it 'orders the campaigns by volume and resolves the campaign id' do
        get url, headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(corpo[:habilitado]).to be(true)
        nomes = corpo[:campanhas].map { |linha| linha[:nome] }
        expect(nomes.first(2)).to eq(['Campanha A', 'Campanha B'])
        primeira = corpo[:campanhas].first
        expect(primeira[:leads]).to eq(2)
        expect(primeira[:campaign_id]).to eq(campanha_com_override)
        expect(corpo[:totais][:leads]).to eq(3)
      end

      it 'marks the campaign configured by an override and the one on the hook default' do
        get url, headers: administrator.create_new_auth_token, as: :json

        com_override = corpo[:campanhas].find { |linha| linha[:nome] == 'Campanha A' }
        padrao = corpo[:campanhas].find { |linha| linha[:nome] == 'Campanha B' }

        expect(com_override[:origem]).to eq('override')
        expect(com_override[:template]).to eq('abertura_custom')
        expect(com_override[:lead_tipo]).to eq('remarketing')
        expect(com_override[:sobrescritos]).to contain_exactly('lead_tipo', 'whatsapp_template_name')
        expect(padrao[:origem]).to eq('padrao')
        expect(padrao[:template]).to eq('abertura_padrao')
        expect(padrao[:sobrescritos]).to eq([])
      end

      it 'reports the routing of each campaign' do
        get url, headers: administrator.create_new_auth_token, as: :json

        linha = corpo[:campanhas].first
        expect(linha[:agente][:nome]).to eq('Atendente virtual')
        expect(linha[:time][:nome]).to eq(team.name)
        expect(corpo[:hooks].first[:pagina]).to eq('Página de teste')
      end

      # O ponto da tela: o que está configurado e o que de fato saiu podem divergir.
      it 'reports the templates actually sent, not only the configured one' do
        get url, headers: administrator.create_new_auth_token, as: :json

        enviados = corpo[:campanhas].first[:templates_enviados]
        expect(enviados.map { |t| t[:nome] }).to contain_exactly('abertura_custom', 'abertura_padrao')
        expect(enviados.sum { |t| t[:leads] }).to eq(2)
      end
    end

    context 'when a campaign is configured but brought no lead in the period' do
      before { criar_hook(overrides: { campanha_com_override => { 'whatsapp_template_name' => 'abertura_custom' } }) }

      it 'still lists it with zero leads' do
        get url, headers: administrator.create_new_auth_token, as: :json

        linha = corpo[:campanhas].find { |item| item[:campaign_id] == campanha_com_override }
        expect(linha[:leads]).to eq(0)
        expect(linha[:template]).to eq('abertura_custom')
      end
    end

    context 'when the hook has an allowlist' do
      before do
        criar_hook(overrides: {}, allowlist: [campanha_sem_override])
        criar_lead(nome_campanha: 'Campanha A', campaign_id: campanha_com_override, template: 'abertura_padrao')
      end

      it 'flags the campaign left out of the allowlist' do
        get url, headers: administrator.create_new_auth_token, as: :json

        expect(corpo[:campanhas].first[:bloqueada]).to be(true)
      end
    end

    context 'when the requester is not an administrator' do
      before do
        criar_hook(overrides: { campanha_com_override => { 'whatsapp_template_name' => 'abertura_custom' } })
        criar_lead(nome_campanha: 'Campanha A', campaign_id: campanha_com_override, template: 'abertura_custom')
      end

      it 'shows the volume but hides the routing configuration' do
        get url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        linha = corpo[:campanhas].first
        expect(linha[:leads]).to eq(1)
        expect(linha[:templates_enviados].first[:nome]).to eq('abertura_custom')
        expect(linha).not_to have_key(:template)
        expect(linha).not_to have_key(:agente)
        expect(corpo[:hooks]).to eq([])
      end
    end

    context 'when a lead lands outside the requested period' do
      before do
        criar_hook
        criar_lead(nome_campanha: 'Campanha A', campaign_id: campanha_com_override,
                   template: 'abertura_padrao').update!(created_at: 90.days.ago)
      end

      it 'is left out of the default window' do
        get url, headers: administrator.create_new_auth_token, as: :json

        expect(corpo[:totais][:leads]).to eq(0)
      end

      it 'comes back when the period covers it' do
        get url, params: { de: 120.days.ago.to_date.to_s }, headers: administrator.create_new_auth_token, as: :json

        expect(corpo[:totais][:leads]).to eq(1)
      end
    end
  end
end
