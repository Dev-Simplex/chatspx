require 'rails_helper'

# Bloco 3.01 — o lar da configuracao do widget em `inbox.additional_attributes`.
# As quatro chaves de topo (A1): widget_profile, widget_triggers, widget_tracking e widget_appearance.
RSpec.describe Inbox, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  describe 'widget config store accessors' do
    it 'reads and writes the four top level keys through additional_attributes' do
      inbox.update!(
        widget_profile: 'marketing',
        widget_triggers: { 'version' => 1, 'enabled' => true },
        widget_tracking: { 'meta_pixel_id' => '1234567890' },
        widget_appearance: { 'position' => 'left' }
      )

      stored = inbox.reload.additional_attributes

      expect(stored['widget_profile']).to eq('marketing')
      expect(stored['widget_triggers']).to eq({ 'version' => 1, 'enabled' => true })
      expect(stored['widget_tracking']).to eq({ 'meta_pixel_id' => '1234567890' })
      expect(stored['widget_appearance']).to eq({ 'position' => 'left' })
      expect(inbox.widget_profile).to eq('marketing')
    end

    it 'keeps an inbox without any of the four keys valid and readable' do
      expect(inbox).to be_valid
      expect(inbox.widget_profile).to be_nil
      expect(inbox.widget_triggers).to be_nil
      expect(inbox.widget_tracking).to be_nil
      expect(inbox.widget_appearance).to be_nil
    end

    it 'does not disturb the pre-existing store accessors of the same jsonb' do
      inbox.update!(pin_mode: 'per_agent', widget_profile: 'support')

      expect(inbox.reload.pin_mode).to eq('per_agent')
      expect(inbox.widget_profile).to eq('support')
    end
  end

  describe 'widget_profile validation' do
    it 'accepts support and marketing' do
      expect(inbox.tap { |i| i.widget_profile = 'support' }).to be_valid
      expect(inbox.tap { |i| i.widget_profile = 'marketing' }).to be_valid
    end

    it 'rejects any other value naming the field' do
      inbox.widget_profile = 'suporte'

      expect(inbox).not_to be_valid
      expect(inbox.errors.attribute_names).to include(:widget_profile)
      expect(inbox.errors[:widget_profile]).to eq(['is not a valid widget profile (accepted values: support, marketing)'])
    end

    # A suite roda com I18n.with_locale(:en) (rails_helper.rb:47), mas esta instalacao serve pt_BR
    # (config/application.rb:48). O aceite de idioma so vale se as duas chaves existirem de verdade.
    it 'carries the same message in pt_BR, which is the locale this installation actually serves' do
      inbox.widget_profile = 'suporte'

      I18n.with_locale(:pt_BR) { inbox.valid? }

      expect(inbox.errors[:widget_profile]).to eq(['não é um perfil de widget válido (valores aceitos: support, marketing)'])
    end
  end

  describe 'widget config type validation' do
    %i[widget_triggers widget_tracking widget_appearance].each do |key|
      it "rejects a non-object value for #{key}" do
        inbox.public_send("#{key}=", 'nope')

        expect(inbox).not_to be_valid
        expect(inbox.errors[key]).to eq(['must be a JSON object'])
      end
    end
  end

  describe 'the secret deny list (3.01; 5.01 apenas a amplia)' do
    it 'rejects a key ending in _token at the top level of widget_tracking' do
      inbox.widget_tracking = { 'meta_pixel_id' => '123', 'access_token' => 'EAAG-secret' }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_tracking])
        .to eq(['does not accept secrets: the key "access_token" belongs in the credentials screen, never here'])
    end

    it 'rejects a key ending in _secret nested inside an object' do
      inbox.widget_tracking = { 'ga4' => { 'measurement_id' => 'G-1', 'api_secret' => 'shh' } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_tracking])
        .to eq(['does not accept secrets: the key "api_secret" belongs in the credentials screen, never here'])
    end

    it 'rejects a secret nested inside an array of objects' do
      inbox.widget_triggers = { 'triggers' => [{ 'id' => 'time_on_page', 'webhook_secret' => 'shh' }] }

      expect(inbox).not_to be_valid
      # O schema de 3.02 tambem recusa a chave como desconhecida; a mensagem de segredo tem de estar la
      # de todo jeito, porque e ela que diz ao administrador ONDE a credencial deve morar.
      expect(inbox.errors[:widget_triggers])
        .to include('does not accept secrets: the key "webhook_secret" belongs in the credentials screen, never here')
    end

    it 'rejects the bare keys token and secret' do
      inbox.widget_appearance = { 'token' => 'abc' }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_appearance].first).to include('"token"')
    end

    # A garantia do 3.01 continua: a lista negativa NAO pode marcar como segredo um nome que
    # apenas contem "token" no meio. O que mudou e o mecanismo do teste — o 5.01 fechou o
    # schema de `widget_tracking` com `additionalProperties: false`, entao um campo inventado
    # como `tokenizer_mode` passa a ser recusado por NAO SER DECLARADO, nao por parecer segredo.
    # Testar pela validade do modelo passou a medir a outra coisa; aqui se pergunta ao scanner.
    it 'accepts public identifiers that merely contain the word token in the middle' do
      valor = { 'tokenizer_mode' => 'strict', 'meta_pixel_id' => '123' }

      expect(WidgetSecretScanner.offending_key_name(valor)).to be_nil
      expect(WidgetSecretScanner.offending_value_holder(valor)).to be_nil
    end

    it 'does not police keys outside the four widget keys' do
      inbox.additional_attributes = { 'some_other_token' => 'kept' }

      expect(inbox).to be_valid
    end
  end
end
