# frozen_string_literal: true

require 'rails_helper'

# 4.22 — a RAMPA. O aceite que este arquivo carrega e o mais curto de enunciar e o mais
# facil de quebrar: "nunca as duas ligadas".
RSpec.describe Widget::CampaignImportService do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  def campanha(regras = { 'url' => 'https://site.com/precos', 'time_on_page' => 15 })
    create(:campaign, account: account, inbox: inbox, campaign_type: :ongoing,
                      enabled: true, trigger_rules: regras)
  end

  def gatilhos(caixa = inbox)
    caixa.reload.additional_attributes['widget_triggers']
  end

  describe 'as duas metades, juntas' do
    it 'cria o gatilho equivalente E desativa a campanha' do
      alvo = campanha

      described_class.new(campaign: alvo).perform

      expect(gatilhos['enabled']).to be(true)
      expect(alvo.reload.enabled).to be(false)
    end

    it 'nunca deixa as duas ligadas — o aceite, dito como asserção' do
      alvo = campanha

      described_class.new(campaign: alvo).perform

      ligadas = [gatilhos['enabled'], alvo.reload.enabled]
      expect(ligadas).to eq([true, false])
    end

    it 'não desativa a campanha quando a escrita do gatilho falha' do
      alvo = campanha
      allow(inbox).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(inbox))
      allow(alvo).to receive(:inbox).and_return(inbox)

      expect { described_class.new(campaign: alvo).perform }.to raise_error(ActiveRecord::RecordInvalid)
      expect(alvo.reload.enabled).to be(true)
    end
  end

  describe 'o que "equivalente" quer dizer' do
    it 'traduz time_on_page para o gatilho de tempo, ligado nas duas plataformas' do
      described_class.new(campaign: campanha).perform

      tempo = gatilhos['triggers'].find { |t| t['id'] == 'time_on_page' }
      expect(tempo['desktop']).to eq({ 'enabled' => true, 'value' => 15 })
      expect(tempo['mobile']).to eq({ 'enabled' => true, 'value' => 15 })
    end

    it 'traduz a URL para audiência com operador `contains`, e não `equals`' do
      described_class.new(campaign: campanha).perform

      # `equals` deixaria de disparar em páginas que hoje disparam — a campanha legada
      # casa por inclusão. Seria regressão silenciosa dentro da própria migração.
      expect(gatilhos['audience']['url']).to eq(
        { 'operator' => 'contains', 'values' => ['https://site.com/precos'] }
      )
    end

    it 'trata campanha sem tempo declarado como disparo imediato' do
      described_class.new(campaign: campanha({ 'url' => 'https://site.com' })).perform

      tempo = gatilhos['triggers'].find { |t| t['id'] == 'time_on_page' }
      expect(tempo['desktop']['value']).to eq(0)
    end

    it 'não escreve audiência quando a campanha não tem URL — vale para o site inteiro' do
      described_class.new(campaign: campanha({ 'time_on_page' => 5 })).perform

      expect(gatilhos['audience']).to be_nil
    end

    it 'corta um tempo absurdo no teto do schema em vez de derrubar a importação' do
      described_class.new(campaign: campanha({ 'time_on_page' => 999_999 })).perform

      tempo = gatilhos['triggers'].find { |t| t['id'] == 'time_on_page' }
      expect(tempo['desktop']['value']).to eq(86_400)
    end

    it 'NÃO copia o texto da campanha para dentro dos gatilhos' do
      alvo = campanha
      described_class.new(campaign: alvo).perform

      expect(gatilhos.to_json).not_to include(alvo.message)
      expect(gatilhos.keys).not_to include('message', 'title')
    end

    it 'produz configuração que o schema aceita' do
      described_class.new(campaign: campanha).perform

      erros = JSONSchemer.schema(WidgetTriggersSchema::SCHEMA).validate(gatilhos).to_a
      expect(erros).to eq([])
    end
  end

  describe 'importar a segunda campanha' do
    it 'preserva o que já existia em vez de sobrescrever a configuração' do
      inbox.update!(additional_attributes: inbox.additional_attributes.merge(
        'widget_triggers' => { 'enabled' => true, 'approach' => 'discreet',
                               'triggers' => [{ 'id' => 'exit_intent', 'desktop' => { 'enabled' => true } }] }
      ))

      described_class.new(campaign: campanha).perform

      ids = gatilhos['triggers'].map { |t| t['id'] }
      expect(ids).to contain_exactly('exit_intent', 'time_on_page')
      expect(gatilhos['approach']).to eq('discreet')
    end

    it 'substitui o gatilho de tempo em vez de criar um segundo' do
      described_class.new(campaign: campanha({ 'time_on_page' => 10 })).perform
      described_class.new(campaign: campanha({ 'time_on_page' => 40 })).perform

      tempos = gatilhos['triggers'].select { |t| t['id'] == 'time_on_page' }
      expect(tempos.size).to eq(1)
      expect(tempos.first['desktop']['value']).to eq(40)
    end
  end

  describe 'o que não é importável' do
    it 'recusa campanha que não é de chat ao vivo' do
      whatsapp = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      alvo = create(:campaign, account: account, inbox: whatsapp.inbox, campaign_type: :one_off, enabled: true)

      expect { described_class.new(campaign: alvo).perform }
        .to raise_error(described_class::NotImportable, /chat ao vivo/)
    end

    it 'recusa campanha inexistente sem estourar NoMethodError' do
      expect { described_class.new(campaign: nil).perform }
        .to raise_error(described_class::NotImportable, /inexistente/)
    end
  end
end
