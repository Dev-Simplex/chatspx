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

  # Um canal que responde `message_templates` como o Cloud API responde: é dele que a tela
  # tira o que oferecer e é contra ele que a validação conta as variáveis.
  #
  # `abertura_uma_variavel` e `abertura_sem_variavel` são o par que produz o #132000 quando
  # a configuração troca um pelo outro sem trocar os campos.
  let(:templates_do_canal) do
    [
      { 'name' => 'abertura_padrao', 'status' => 'APPROVED', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, tudo bem?' }] },
      { 'name' => 'abertura_duas_variaveis', 'status' => 'APPROVED', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, vi seu interesse em {{2}}.' }] },
      { 'name' => 'abertura_sem_variavel', 'status' => 'APPROVED', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi! Somos da equipe.' }] },
      { 'name' => 'abertura_com_foto', 'status' => 'APPROVED', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' },
                         { 'type' => 'BODY', 'text' => 'Oi {{1}}!' }] },
      { 'name' => 'abertura_em_analise', 'status' => 'PENDING', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}!' }] }
    ]
  end

  # Inbox de canal WhatsApp — a única em que template vale alguma coisa. Os transients do
  # factory desligam o sync e a validação do provider, então nada aqui sai para a rede.
  let(:canal_whatsapp) do
    create(:channel_whatsapp, account: account, sync_templates: false,
                              validate_provider_config: false, message_templates: templates_do_canal)
  end
  let(:inbox_whatsapp) { canal_whatsapp.inbox }

  def criar_hook(overrides: {}, allowlist: nil, extras: {})
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
    }.merge(extras)
    settings['allowed_campaign_ids'] = allowlist unless allowlist.nil?
    create(:integrations_hook, account: account, app_id: 'meta_lead_ads', settings: settings)
  end

  def overrides_do(hook)
    hook.reload.settings['campaign_overrides']
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

    context 'when the target inbox is a WhatsApp channel' do
      before { criar_hook(extras: { 'target_inbox_id' => inbox_whatsapp.id }) }

      it 'offers only the templates the channel has approved' do
        get url, headers: administrator.create_new_auth_token, as: :json

        oferecidos = corpo[:hooks].first[:opcoes][:templates]
        expect(oferecidos.map { |item| item[:nome] }).not_to include('abertura_em_analise')
        expect(oferecidos.find { |item| item[:nome] == 'abertura_duas_variaveis' }[:variaveis]).to eq(%w[1 2])
      end

      # A tela mostra o template de mídia, mas marcado: some-lo faria o admin procurar
      # por um template que existe e está aprovado.
      it 'marks the templates the lead opening message cannot send' do
        get url, headers: administrator.create_new_auth_token, as: :json

        oferecidos = corpo[:hooks].first[:opcoes][:templates]
        expect(oferecidos.find { |item| item[:nome] == 'abertura_com_foto' }[:impedimento]).to eq('cabecalho_de_midia')
        expect(oferecidos.find { |item| item[:nome] == 'abertura_padrao' }[:impedimento]).to be_nil
      end

      it 'does not hand the options to a non-administrator' do
        get url, headers: agent.create_new_auth_token, as: :json

        expect(corpo[:hooks]).to eq([])
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/lead_campaigns' do
    let(:hook) { criar_hook(extras: { 'target_inbox_id' => inbox_whatsapp.id }) }

    def salvar(quem: administrator, campanha: campanha_com_override, **roteamento)
      put url, params: { campaign_id: campanha, roteamento: roteamento },
               headers: quem.create_new_auth_token, as: :json
    end

    context 'when it is not an administrator' do
      before { hook }

      it 'refuses the edit' do
        salvar(template: 'abertura_padrao', campos: ['first_name'], quem: agent)

        expect(response).to have_http_status(:unauthorized)
        expect(overrides_do(hook)).to eq({})
      end
    end

    context 'when the combination matches the approved template' do
      before { hook }

      it 'saves template, language, fields, agent and team' do
        outro_time = create(:team, account: account)
        salvar(template: 'abertura_duas_variaveis', campos: %w[first_name campaign_name], time: outro_time.id)

        expect(response).to have_http_status(:success)
        gravado = overrides_do(hook)[campanha_com_override]
        expect(gravado['whatsapp_template_name']).to eq('abertura_duas_variaveis')
        expect(gravado['whatsapp_template_body_fields']).to eq('first_name,campaign_name')
        expect(gravado['assign_team_id']).to eq(outro_time.id.to_s)
        # O idioma não é digitado: vem do template escolhido, porque a Meta casa o par.
        expect(gravado['whatsapp_template_locale']).to eq('pt_BR')
      end

      # Sem isto o default `first_name` mandaria {{1}} para um template sem variável — que é
      # exatamente o #132000 que esta tela existe para evitar.
      it 'writes the explicit no-variable marker for a template without variables' do
        salvar(template: 'abertura_sem_variavel', campos: [])

        expect(response).to have_http_status(:success)
        expect(overrides_do(hook)[campanha_com_override]['whatsapp_template_body_fields']).to eq('none')
      end

      it 'returns the resolved configuration, not what the form sent' do
        salvar(template: 'abertura_sem_variavel', campos: [])

        expect(corpo[:campanha][:template]).to eq('abertura_sem_variavel')
        expect(corpo[:campanha][:origem]).to eq('override')
        expect(corpo[:campanha][:agente][:nome]).to eq('Atendente virtual')
      end
    end

    context 'when the combination would produce Meta error #132000' do
      before { hook }

      it 'refuses more fields than the template takes' do
        salvar(template: 'abertura_padrao', campos: %w[first_name campaign_name])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(corpo[:erros].first[:campo]).to eq('campos')
        expect(corpo[:erros].first[:mensagem]).to include('1').and include('2')
        expect(overrides_do(hook)).to eq({})
      end

      it 'refuses fewer fields than the template takes' do
        salvar(template: 'abertura_duas_variaveis', campos: ['first_name'])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(overrides_do(hook)).to eq({})
      end

      it 'refuses a field that does not exist on the lead' do
        salvar(template: 'abertura_padrao', campos: ['renda_mensal'])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(corpo[:erros].first[:mensagem]).to include('renda_mensal')
        expect(overrides_do(hook)).to eq({})
      end

      it 'refuses a template the channel has not approved' do
        salvar(template: 'abertura_em_analise', campos: ['first_name'])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(corpo[:erros].first[:campo]).to eq('template')
        expect(overrides_do(hook)).to eq({})
      end

      # A abertura do lead só manda parâmetros do corpo: o cabeçalho chegaria vazio.
      it 'refuses a template with a media header' do
        salvar(template: 'abertura_com_foto', campos: ['first_name'])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(overrides_do(hook)).to eq({})
      end
    end

    # O que a engine usa é o override MAIS o padrão do hook. Limpar o override sem olhar o
    # padrão criaria em silêncio a mesma configuração quebrada.
    context 'when clearing the override falls back to a broken hook default' do
      let(:hook) do
        criar_hook(
          overrides: { campanha_com_override => { 'whatsapp_template_name' => 'abertura_padrao',
                                                  'whatsapp_template_body_fields' => 'first_name' } },
          extras: { 'target_inbox_id' => inbox_whatsapp.id,
                    'whatsapp_template_name' => 'abertura_duas_variaveis',
                    'whatsapp_template_body_fields' => 'first_name' }
        )
      end

      before { hook }

      it 'refuses to clear it and says which template does not add up' do
        salvar(template: '', campos: [])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(corpo[:erros].first[:mensagem]).to include('abertura_duas_variaveis')
        expect(overrides_do(hook)[campanha_com_override]['whatsapp_template_name']).to eq('abertura_padrao')
      end
    end

    context 'when the override is cleared and the hook default adds up' do
      let(:hook) do
        criar_hook(
          overrides: { campanha_com_override => { 'whatsapp_template_name' => 'abertura_sem_variavel',
                                                  'whatsapp_template_body_fields' => 'none' } },
          extras: { 'target_inbox_id' => inbox_whatsapp.id }
        )
      end

      before { hook }

      # Override que sobrasse só com a autoria continuaria contando como override na tela.
      it 'removes the campaign entry so it goes back to inheriting' do
        salvar(template: '', campos: [])

        expect(response).to have_http_status(:success)
        expect(overrides_do(hook)).to eq({})
        expect(corpo[:campanha][:origem]).to eq('padrao')
        expect(corpo[:campanha][:template]).to eq('abertura_padrao')
      end
    end

    context 'when the routing points at something that is not in the account' do
      before { hook }

      it 'refuses a team from another account' do
        estranho = create(:team, account: create(:account))
        salvar(template: 'abertura_padrao', campos: ['first_name'], time: estranho.id)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(corpo[:erros].first[:campo]).to eq('time')
      end

      # O espelho nasce junto do assistente (`sync_mirror_agent_bot`); ele não está elegível
      # à inbox alvo, e o AssignmentService o recusaria em silêncio na hora do lead.
      it 'refuses an AI mirror the target inbox does not accept' do
        espelho = create(:captain_assistant, account: account).mirror_agent_bot
        salvar(template: 'abertura_padrao', campos: ['first_name'], agente: espelho.id)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(corpo[:erros].first[:campo]).to eq('agente')
        expect(overrides_do(hook)).to eq({})
      end
    end

    context 'when the campaign has no intake hook answering for it' do
      it 'refuses without touching anything' do
        salvar(template: 'abertura_padrao', campos: ['first_name'])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(corpo[:erros].first[:campo]).to eq('campanha')
      end
    end

    # Hoje o override muda sem rastro nenhum. O registro forense não pode depender do
    # feature flag de audit logs — por isso a autoria também fica no próprio override.
    context 'when the change goes through' do
      before { hook }

      it 'records who changed what' do
        expect { salvar(template: 'abertura_sem_variavel', campos: []) }
          .to change(Audited::Audit.where(auditable_type: 'Integrations::Hook'), :count).by(1)

        registro = Audited::Audit.where(auditable_type: 'Integrations::Hook').last
        expect(registro.user_id).to eq(administrator.id)
        expect(registro.audited_changes.dig('campaign_overrides', campanha_com_override, 'para',
                                            'whatsapp_template_name')).to eq('abertura_sem_variavel')
        expect(overrides_do(hook)[campanha_com_override]['_atualizado_por']).to eq(administrator.available_name)
      end

      # `settings` guarda app_secret e page_access_token: auditoria não é lugar de segredo.
      it 'keeps the hook credentials out of the audit trail' do
        salvar(template: 'abertura_sem_variavel', campos: [])

        registro = Audited::Audit.where(auditable_type: 'Integrations::Hook').last
        expect(registro.audited_changes.to_json).not_to match(/page_access_token|app_secret|verify_token/)
      end
    end
  end
end
