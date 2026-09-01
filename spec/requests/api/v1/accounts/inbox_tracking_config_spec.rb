require 'rails_helper'

# Bloco 5.01 — os DOIS sentidos da recusa, pela API real.
#
# Um: a chave que parece segredo e recusada com 422, e a mensagem manda para a tela de credenciais.
# Dois: salvar a config SEM ela nao apaga nada que ja estava la. O segundo nao e detalhe — o pior
# defeito desta execucao foi o upstream filtrar um campo na leitura enquanto o formulario reenviava
# o objeto inteiro, e abrir "Editar" numa integracao APAGAVA a credencial do cliente. Recusa que
# apaga o que ja existia troca um vazamento por uma perda.
RSpec.describe 'Config publica de tracking da inbox (5.01)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}" }

  let(:config_boa) do
    {
      'meta_pixel_id' => '1234567890',
      'ga4_measurement_id' => 'G-ABC1234567',
      'event_map' => { 'conversation_started' => 'Lead' }
    }
  end

  def patch_inbox(additional_attributes)
    patch base_url,
          headers: admin.create_new_auth_token,
          params: { additional_attributes: additional_attributes },
          as: :json
  end

  def stored_attributes
    get base_url, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['additional_attributes']
  end

  describe 'sentido 1 — a chave que parece segredo e recusada' do
    it 'devolve 422 apontando a tela de credenciais, no idioma da instalacao' do
      patch_inbox(widget_tracking: config_boa.merge('access_token' => 'EAAGm0PX4ZCpsBA0ZDZD1234567890abcdefghij'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('widget_tracking')
      # A requisicao real responde no locale da instalacao (pt_BR, config/application.rb:48) — e o
      # texto que o admin ve no dashboard, nao o :en do rails_helper.
      expect(response.parsed_body['message']).to include('access_token')
      expect(response.parsed_body['message']).to include('tela de credenciais')
    end

    it 'nao grava nada da requisicao recusada — nem as chaves boas que vinham junto' do
      patch_inbox(config_boa.merge('access_token' => 'EAAGm0PX4ZCpsBA0ZDZD1234567890abcdefghij')
                            .then { |t| { widget_tracking: t } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(inbox.reload.widget_tracking).to be_nil
    end

    it 'recusa tambem o valor com cara de credencial sob chave publica' do
      patch_inbox(widget_tracking: { 'event_map' => { 'conversation_started' => 'sk_live_1234567890abcdefghijklmn' } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('tela de credenciais')
      expect(response.parsed_body['message']).not_to include('sk_live')
    end

    it 'recusa chave nao declarada em vez de grava-la para descartar na leitura' do
      patch_inbox(widget_tracking: { 'meta_pixel_id' => '1234567890', 'chave_inventada' => 'x' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('chave_inventada')
      expect(inbox.reload.widget_tracking).to be_nil
    end
  end

  describe 'sentido 2 — salvar sem a chave suspeita nao apaga o que ja estava' do
    before do
      inbox.update!(
        widget_profile: 'marketing',
        widget_tracking: config_boa,
        widget_triggers: { 'version' => 1 },
        widget_appearance: { 'position' => 'left' }
      )
    end

    it 'a tentativa recusada deixa a config anterior INTACTA' do
      patch_inbox(widget_tracking: config_boa.merge('access_token' => 'EAAGm0PX4ZCpsBA0ZDZD1234567890abcdefghij'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(inbox.reload.widget_tracking).to eq(config_boa)
    end

    it 'reenviar a config boa inteira mantem tudo, e nao apaga as outras tres chaves' do
      patch_inbox(widget_tracking: config_boa)

      expect(response).to have_http_status(:success)
      atributos = stored_attributes
      expect(atributos['widget_tracking']).to eq(config_boa)
      expect(atributos['widget_profile']).to eq('marketing')
      expect(atributos['widget_triggers']).to eq({ 'version' => 1 })
      expect(atributos['widget_appearance']).to eq({ 'position' => 'left' })
    end

    it 'salvar OUTRA chave nao mexe no tracking que ja estava' do
      patch_inbox(widget_profile: 'support')

      expect(response).to have_http_status(:success)
      expect(stored_attributes['widget_tracking']).to eq(config_boa)
    end

    it 'atualizar um campo do tracking preserva os outros campos enviados juntos' do
      patch_inbox(widget_tracking: config_boa.merge('meta_pixel_id' => '9876543210'))

      expect(response).to have_http_status(:success)
      tracking = stored_attributes['widget_tracking']
      expect(tracking['meta_pixel_id']).to eq('9876543210')
      expect(tracking['ga4_measurement_id']).to eq('G-ABC1234567')
      expect(tracking['event_map']).to eq({ 'conversation_started' => 'Lead' })
    end
  end

  # ═══ SENTIDO 3 — o rascunho de FABRICA da tela, pelo ENDPOINT real ══════════════════════
  #
  # O spec de modelo prova que a validacao aceita o rascunho. Ele NAO prova que a requisicao
  # chega inteira: entre a tela e a validacao ha strong params, `permitted_params` e o merge
  # raso de `inbox_update_params`. Este bloco fecha esse trecho — e usa o rascunho lido do
  # arquivo do front, nao um hash montado a mao.
  describe 'sentido 3 — a tela salva de primeira numa inbox nova' do
    let(:rascunho_de_fabrica) do
      caminho = 'app/javascript/dashboard/routes/dashboard/settings/inbox/widget/composables/widgetConfigFields.js'
      bloco = Rails.root.join(caminho).read[/DEFAULT_TRACKING = Object\.freeze\(\{(.+?)\n\}\);/m, 1].to_s
      literais = { "''" => '', '{}' => {} }

      bloco.lines.filter_map do |linha|
        linha = linha.strip.delete_suffix(',')
        next if linha.empty? || linha.start_with?('//', '*')

        nome, cru = linha.split(':', 2).map(&:strip)
        [nome, literais.fetch(cru) { raise "valor JS nao reconhecido: #{nome}: #{cru}" }]
      end.to_h
    end

    it 'o rascunho foi mesmo lido do front' do
      expect(rascunho_de_fabrica.keys).to match_array(WidgetTrackingProjection::PUBLIC_KEYS)
    end

    it 'PATCH com o rascunho de fabrica devolve 200, e nao o 422 de ontem' do
      patch_inbox(widget_tracking: rascunho_de_fabrica)

      expect(response).to have_http_status(:success)
    end

    it 'e o que fica gravado nao carrega os quatro vazios' do
      patch_inbox(widget_tracking: rascunho_de_fabrica.merge('install_tags' => { 'meta' => true }))

      expect(response).to have_http_status(:success)
      tracking = stored_attributes['widget_tracking']
      expect(tracking['install_tags']).to eq({ 'meta' => true })
      expect(tracking.keys).not_to include('meta_pixel_id', 'ga4_measurement_id', 'google_ads_send_to', 'consent_mode')
    end

    it 'e o 422 continua vindo quando ha o que recusar — vazio nao virou passe livre' do
      patch_inbox(widget_tracking: rascunho_de_fabrica.merge('meta_pixel_id' => 'EAAGm0PX4ZCpsBA0'))

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
