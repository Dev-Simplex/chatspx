require 'rails_helper'

# Bloco 3.04 — as quatro chaves da Onda 2 entregues ao widget, NOS DOIS montadores.
#
# A suite de paridade (0.6, `widget_configuration_builder_parity_spec.rb`) garante que as chaves
# existam nos dois. Este spec garante o resto: que o CONTEUDO seja o mesmo, que a aparencia venha
# resolvida, que a abordagem venha resolvida por dentro dos gatilhos, e que `widget_tracking` seja
# projecao — nunca o hash cru do banco.
RSpec.describe 'Widget configuration payload', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  # O objeto `window.chatwootWebChannel` do ERB, lido de volta como Hash.
  def erb_channel_config
    get widget_url(website_token: web_widget.website_token, cw_conversation: token)
    expect(response).to have_http_status(:ok)

    body = response.body.match(/window\.chatwootWebChannel\s*=\s*\{(?<config>.*?)^\s*\}\s*window\.chatwootPubsubToken/m)
    raise 'window.chatwootWebChannel not found in the rendered ERB' if body.nil?

    body[:config]
  end

  def erb_value(key)
    raw = erb_channel_config[/^\s*#{key}:\s*(?<value>.*?),?\s*$/m, :value]
    raise "key #{key} not found in window.chatwootWebChannel" if raw.nil?

    raw.start_with?("'") ? raw.delete("'") : JSON.parse(raw)
  end

  def jbuilder_config
    post '/api/v1/widget/config',
         params: { website_token: web_widget.website_token },
         headers: { 'X-Auth-Token' => token },
         as: :json
    expect(response).to have_http_status(:ok)

    response.parsed_body.fetch('website_channel_config')
  end

  describe 'an inbox that never opened the configuration screen' do
    it 'still gets a complete appearance, in both builders' do
      expected = WidgetAppearanceSchema::DEFAULTS

      expect(erb_value('widgetAppearance')).to eq(expected)
      expect(jbuilder_config['widget_appearance']).to eq(expected)
    end

    it 'is read as the support profile, in both builders (A4: no backfill)' do
      expect(erb_value('widgetProfile')).to eq('support')
      expect(jbuilder_config['widget_profile']).to eq('support')
    end

    it 'gets the eleven flat flags, identical in both builders' do
      erb_flags = erb_value('profileConfig')

      expect(erb_flags.keys).to match_array(
        %w[showKnowledgeBase showConversationList teaserEnabled teaserDelayMs teaserScrollPercent
           captureFlow primaryExit csatOnResolve emailContinuity homeLayout aiLabelPersistent]
      )
      expect(jbuilder_config['profile_config']).to eq(erb_flags)
    end

    it 'gets the approach resolved inside the triggers, in both builders' do
      expected = { 'approach' => 'bold', 'approach_mobile' => 'bold', 'degrade_on_return' => true }

      expect(erb_value('widgetTriggers')).to eq(expected)
      expect(jbuilder_config['widget_triggers']).to eq(expected)
    end

    it 'gets an empty tracking projection, not null' do
      expect(erb_value('widgetTracking')).to eq({})
      expect(jbuilder_config['widget_tracking']).to eq({})
    end
  end

  describe 'a fully configured marketing inbox' do
    before do
      inbox.update!(
        widget_profile: 'marketing',
        widget_triggers: { 'version' => 1, 'enabled' => true, 'approach' => 'aggressive',
                           'triggers' => [{ 'id' => 'time_on_page', 'desktop' => { 'enabled' => true, 'value' => 15 } }] },
        widget_tracking: { 'meta_pixel_id' => '1234567890', 'event_map' => { 'conversation_started' => 'Lead' } },
        widget_appearance: { 'position' => 'left', 'launcher_text' => 'Fale com a gente' }
      )
    end

    it 'delivers the four keys with the same content in both builders' do
      erb = { profile: erb_value('widgetProfile'), triggers: erb_value('widgetTriggers'),
              tracking: erb_value('widgetTracking'), appearance: erb_value('widgetAppearance') }
      json = jbuilder_config

      expect(erb[:profile]).to eq('marketing')
      expect(json['widget_profile']).to eq('marketing')
      expect(erb[:triggers]).to eq(json['widget_triggers'])
      expect(erb[:tracking]).to eq(json['widget_tracking'])
      expect(erb[:appearance]).to eq(json['widget_appearance'])
    end

    it 'fills the appearance defaults around what was configured' do
      appearance = erb_value('widgetAppearance')

      expect(appearance['position']).to eq('left')
      expect(appearance['launcher_text']).to eq('Fale com a gente')
      expect(appearance['theme']).to eq('light')
      expect(appearance['launcher_icon']).to eq('default')
      expect(appearance['home_intents']).to eq([])
    end

    it 'keeps the configured triggers and refuses to let mobile inherit aggressive' do
      triggers = erb_value('widgetTriggers')

      expect(triggers['triggers'].first['desktop']).to eq({ 'enabled' => true, 'value' => 15 })
      expect(triggers['approach']).to eq('aggressive')
      expect(triggers['approach_mobile']).to eq('bold')
    end

    it 'resolves the marketing flags for the widget to consume' do
      flags = erb_value('profileConfig')

      expect(flags['homeLayout']).to eq('marketing')
      expect(flags['showKnowledgeBase']).to be(false)
      expect(flags['teaserEnabled']).to be(true)
      expect(jbuilder_config['profile_config']).to eq(flags)
    end
  end

  describe 'no secret leaves through either builder' do
    before do
      # Gravado POR BAIXO da validacao de 3.01, de proposito: a lista negativa barra a escrita pela
      # API, mas a projecao existe para o caso de um segredo entrar por outro caminho — console,
      # import, migration de terceiro. Se a leitura fosse o hash cru, ele sairia no HTML do cliente.
      inbox.update_column(
        :additional_attributes,
        { 'widget_tracking' => { 'meta_pixel_id' => '1234567890', 'access_token' => 'EAAG-super-secret',
                                 'ga4' => { 'api_secret' => 'shh' } } }
      )
    end

    it 'the ERB delivers only the public identifiers' do
      expect(erb_value('widgetTracking')).to eq({ 'meta_pixel_id' => '1234567890' })
    end

    it 'the jbuilder delivers only the public identifiers' do
      expect(jbuilder_config['widget_tracking']).to eq({ 'meta_pixel_id' => '1234567890' })
    end

    it 'neither builder carries the secret value anywhere in the payload' do
      erb_body = erb_channel_config
      json_body = jbuilder_config.to_json

      expect(erb_body).not_to include('EAAG-super-secret')
      expect(erb_body).not_to include('access_token')
      expect(erb_body).not_to include('api_secret')
      expect(json_body).not_to include('EAAG-super-secret')
      expect(json_body).not_to include('access_token')
      expect(json_body).not_to include('api_secret')
    end

    it 'the four widget keys carry no key or value matching token/secret in either builder' do
      erb_widget_keys = %w[widgetProfile profileConfig widgetTriggers widgetTracking widgetAppearance]
                        .index_with { |key| erb_value(key) }
      json = jbuilder_config
      json_widget_keys = json.slice('widget_profile', 'profile_config', 'widget_triggers',
                                    'widget_tracking', 'widget_appearance')

      expect(erb_widget_keys.to_json).not_to match(/token|secret/i)
      expect(json_widget_keys.to_json).not_to match(/token|secret/i)
    end
  end
end
