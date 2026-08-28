require 'rails_helper'

# Bloco 3.07 — o PAYLOAD DA TELA contra a validacao do servidor.
#
# Cada trilha testa o SEU formato: o front cobre o que a tela monta, o back cobre o que o schema
# aceita, e ninguem roda o payload da tela contra o schema. Foi assim que a troca de perfil chegou a
# este bloco propondo gravar a STRING `'teaser_8s_30pct'` em `widget_triggers` — um campo que
# `WidgetConfigurable#ensure_widget_config_objects` exige que seja objeto.
#
# O que se esperava era 422. O que esta MEDIDO abaixo e pior: `permit` declara `widget_triggers: {}`,
# entao o escalar nao e recusado — e descartado em silencio, com 200 e sem erro nenhum. A tela diria
# "salvo" e o teaser nunca existiria.
#
# Este spec le o preset do arquivo JS de verdade e MONTA o payload com o que ele declara. Se o front
# mudar a forma do preset, este spec cai nomeando a diferenca — que e o unico jeito de a trava
# sobreviver a proxima edicao.
RSpec.describe 'Widget profile switch payload', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}" }

  # `app/javascript/.../composables/widgetTriggersContract.js` — a mesma fonte que
  # `WidgetProfileSelector` usa para propor "ligar o teaser com o gatilho composto".
  def recommended_triggers_from_javascript
    path = Rails.root.join(
      'app/javascript/dashboard/routes/dashboard/settings/inbox/widget/composables/widgetTriggersContract.js'
    )
    bloco = path.read[/export const RECOMMENDED_TRIGGERS = Object\.freeze\(\[(.*?)\]\);/m, 1]
    raise 'RECOMMENDED_TRIGGERS nao encontrado no arquivo JS' if bloco.blank?

    plataforma = /\{\s*enabled:\s*(true|false),\s*value:\s*(\d+)\s*\}/
    bloco.scan(/id:\s*'([a-z_]+)',\s*desktop:\s*#{plataforma},\s*mobile:\s*#{plataforma}/m)
         .map do |id, desktop_enabled, desktop_value, mobile_enabled, mobile_value|
      {
        'id' => id,
        'desktop' => { 'enabled' => desktop_enabled == 'true', 'value' => desktop_value.to_i },
        'mobile' => { 'enabled' => mobile_enabled == 'true', 'value' => mobile_value.to_i }
      }
    end
  end

  def patch_inbox(params)
    patch base_url, headers: admin.create_new_auth_token, params: params, as: :json
  end

  describe 'the structure the screen now sends' do
    it 'reads two triggers from the front contract — 8 s on page AND 30% scroll' do
      # A trava da trava: se o regex acima parar de casar, o resto do arquivo passaria no vacuo.
      expect(recommended_triggers_from_javascript).to eq(
        [
          { 'id' => 'time_on_page', 'desktop' => { 'enabled' => true, 'value' => 8 }, 'mobile' => { 'enabled' => true, 'value' => 8 } },
          { 'id' => 'scroll_depth', 'desktop' => { 'enabled' => true, 'value' => 30 }, 'mobile' => { 'enabled' => true, 'value' => 30 } }
        ]
      )
    end

    it 'persists the whole profile switch in one PATCH' do
      patch_inbox(
        csat_survey_enabled: false,
        channel: { pre_chat_form_enabled: true, continuity_via_email: false },
        additional_attributes: {
          widget_profile: 'marketing',
          widget_triggers: { 'enabled' => true, 'triggers' => recommended_triggers_from_javascript }
        }
      )

      expect(response).to have_http_status(:success)

      inbox.reload
      expect(inbox.widget_profile).to eq('marketing')
      expect(inbox.csat_survey_enabled).to be(false)
      expect(inbox.channel.pre_chat_form_enabled).to be(true)
      expect(inbox.channel.continuity_via_email).to be(false)
      expect(inbox.widget_triggers['enabled']).to be(true)
      expect(inbox.widget_triggers['triggers'].map { |trigger| trigger['id'] }).to eq(%w[time_on_page scroll_depth])
    end

    # O que esta medido aqui, e que e PIOR do que o 422 que se esperava: mandar a string produz
    # 200 e NENHUM erro. `permit` declara `widget_triggers: {}` (inboxes_controller.rb:269), entao
    # um escalar nao e recusado — e DESCARTADO em silencio. A tela diria "salvo", o administrador
    # sairia certo de que ligou o teaser, e o campo continuaria vazio para sempre.
    it 'silently DISCARDS the preset name as a string — the defect this block removed' do
      # Forcando a condicao ruim: e exatamente o que o aplicador ingenuo escreveria a partir de
      # `PROFILE_PROPOSALS[...].value`. Sem esta assercao, a de cima passaria mesmo que o valor
      # errado tambem "funcionasse", e a correcao nao estaria medida.
      patch_inbox(additional_attributes: { widget_triggers: 'teaser_8s_30pct' })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['additional_attributes']).not_to have_key('widget_triggers')
      expect(inbox.reload.widget_triggers).to be_nil
    end

    it 'and the model would refuse it, so the silence is the strong params, not the validation' do
      # O outro lado da mesma moeda: a validacao existe e funciona. Quem apaga o erro e o `permit`.
      inbox.widget_triggers = 'teaser_8s_30pct'

      expect(inbox).not_to be_valid
      expect(inbox.errors.attribute_names).to include(:widget_triggers)
    end

    it 'switching the profile does not erase the other three keys' do
      inbox.update!(
        additional_attributes: {
          'widget_appearance' => { 'position' => 'left' },
          'widget_tracking' => { 'meta_pixel_id' => '1234567890' }
        }
      )

      patch_inbox(
        additional_attributes: {
          widget_profile: 'marketing',
          widget_triggers: { 'enabled' => true, 'triggers' => recommended_triggers_from_javascript }
        }
      )

      expect(response).to have_http_status(:success)

      inbox.reload
      # "Nada e apagado" e a frase do aceite, e o merge raso do `#update` e o mecanismo que a sustenta.
      expect(inbox.widget_appearance).to eq({ 'position' => 'left' })
      expect(inbox.widget_tracking).to eq({ 'meta_pixel_id' => '1234567890' })
    end

    it 'the declined proposal is simply absent from the PATCH, and the stored value survives' do
      inbox.update!(csat_survey_enabled: true)

      # O administrador desmarcou "desligar o CSAT": a tela nao manda a chave.
      patch_inbox(additional_attributes: { widget_profile: 'marketing' })

      expect(response).to have_http_status(:success)
      expect(inbox.reload.csat_survey_enabled).to be(true)
    end
  end
end
