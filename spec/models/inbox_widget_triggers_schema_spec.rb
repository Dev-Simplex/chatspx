require 'rails_helper'

# Bloco 3.02 — o schema dos gatilhos, validado por json_schemer. A mensagem tem de NOMEAR o campo:
# um 422 que diz apenas "invalido" devolve o administrador ao suporte.
RSpec.describe Inbox, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  let(:valid_triggers) do
    {
      'version' => 1,
      'enabled' => true,
      'defaults' => { 'cooldown_seconds' => 86_400, 'max_per_session' => 1 },
      'triggers' => [
        { 'id' => 'time_on_page', 'desktop' => { 'enabled' => true, 'value' => 15 },
          'mobile' => { 'enabled' => true, 'value' => 25 }, 'cooldown_seconds' => 86_400 },
        { 'id' => 'element_click', 'desktop' => { 'enabled' => false, 'selector' => '#quero-orcamento' } }
      ],
      'audience' => {
        'url' => { 'operator' => 'contains', 'values' => ['/planos'] },
        'utm' => { 'utm_source' => ['google'] },
        'device' => %w[desktop mobile]
      }
    }
  end

  it 'persists a valid object untouched' do
    inbox.update!(widget_triggers: valid_triggers)

    expect(inbox.reload.widget_triggers).to eq(valid_triggers)
  end

  it 'accepts a partial object — every field is optional' do
    inbox.widget_triggers = { 'enabled' => false }

    expect(inbox).to be_valid
  end

  it 'rejects a negative value naming the field' do
    inbox.widget_triggers = { 'triggers' => [{ 'id' => 'time_on_page', 'desktop' => { 'enabled' => true, 'value' => -5 } }] }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_triggers]).to eq(['has an invalid value at "triggers/0/desktop/value": must be greater than or equal to 0'])
  end

  it 'rejects an unknown trigger id naming the field and listing what is accepted' do
    inbox.widget_triggers = { 'triggers' => [{ 'id' => 'mouse_shake' }] }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_triggers].first).to start_with('has an invalid value at "triggers/0/id": value is not allowed (accepted:')
    expect(inbox.errors[:widget_triggers].first).to include('time_on_page')
  end

  it 'rejects an empty selector naming the field' do
    inbox.widget_triggers = { 'triggers' => [{ 'id' => 'element_click', 'desktop' => { 'enabled' => true, 'selector' => '' } }] }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_triggers])
      .to eq(['has an invalid value at "triggers/0/desktop/selector": needs at least 1 character'])
  end

  it 'rejects a trigger entry without an id' do
    inbox.widget_triggers = { 'triggers' => [{ 'desktop' => { 'enabled' => true } }] }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_triggers]).to eq(['has an invalid value at "triggers/0": missing required field: id'])
  end

  it 'rejects an unknown top level field' do
    inbox.widget_triggers = { 'enabled' => true, 'tirggers' => [] }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_triggers]).to eq(['has an invalid value at "tirggers": unknown field'])
  end

  it 'rejects a wrong type naming the field' do
    inbox.widget_triggers = { 'enabled' => 'yes' }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_triggers]).to eq(['has an invalid value at "enabled": must be of type boolean'])
  end

  it 'reports every offending field, not only the first' do
    inbox.widget_triggers = { 'enabled' => 'yes', 'version' => 0 }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_triggers].size).to eq(2)
    expect(inbox.errors[:widget_triggers].join(' ')).to include('enabled').and include('version')
  end

  # --- bloco 4.04: T3.2 (UTM e visitante) e T3.5 ("quando nao aparecer") ---

  describe 'the segmentation the screen writes (T3.2)' do
    it 'persists the five utm params and the visitor kind untouched' do
      full = {
        'audience' => {
          'utm' => WidgetTriggersSchema::UTM_PARAMS.index_with { |param| ["#{param}-value"] },
          'visitor' => 'returning'
        }
      }

      inbox.update!(widget_triggers: full)

      expect(inbox.reload.widget_triggers).to eq(full)
    end

    it 'rejects a misspelled utm param naming the key, instead of storing a rule that never fires' do
      inbox.widget_triggers = { 'audience' => { 'utm' => { 'utm_sorce' => ['google'] } } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers]).to eq(['has an invalid value at "audience/utm/utm_sorce": unknown field'])
    end

    it 'rejects an unknown visitor kind listing what is accepted' do
      inbox.widget_triggers = { 'audience' => { 'visitor' => 'loyal' } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers].first).to start_with('has an invalid value at "audience/visitor": value is not allowed (accepted:')
      expect(inbox.errors[:widget_triggers].first).to include('returning')
    end

    it 'rejects an empty utm value — a blank chip matches every visitor, which is the opposite of segmenting' do
      inbox.widget_triggers = { 'audience' => { 'utm' => { 'utm_source' => [''] } } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers]).to eq(['has an invalid value at "audience/utm/utm_source/0": needs at least 1 character'])
    end
  end

  describe 'the suppression rules (T3.5)' do
    it 'persists the three rules untouched' do
      full = {
        'suppress' => { 'cookie_banner' => true, 'min_viewport_width' => 768, 'outside_business_hours' => true }
      }

      inbox.update!(widget_triggers: full)

      expect(inbox.reload.widget_triggers).to eq(full)
    end

    it 'rejects a viewport width above the cap naming the field' do
      inbox.widget_triggers = { 'suppress' => { 'min_viewport_width' => WidgetTriggersSchema::MAX_VIEWPORT_WIDTH + 1 } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers])
        .to eq(["has an invalid value at \"suppress/min_viewport_width\": must be less than or equal to #{WidgetTriggersSchema::MAX_VIEWPORT_WIDTH}"])
    end

    it 'rejects an unknown suppression rule instead of dropping it in silence' do
      inbox.widget_triggers = { 'suppress' => { 'cookie_bannner' => true } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers]).to eq(['has an invalid value at "suppress/cookie_bannner": unknown field'])
    end
  end

  # O que a tela grava tem de CHEGAR ao visitante: `resolved_widget_triggers` e o que o payload de
  # boot publica, e ele merge-ia a abordagem por cima do gravado. Uma chave nova que ele nao
  # carregue e uma tela que salva e um widget que nunca sabe.
  it 'delivers the new segmentation and suppression in the boot payload' do
    inbox.update!(widget_triggers: {
                    'audience' => { 'utm' => { 'utm_source' => ['google'] }, 'visitor' => 'new' },
                    'suppress' => { 'cookie_banner' => true, 'min_viewport_width' => 768 }
                  })

    delivered = inbox.reload.resolved_widget_triggers

    expect(delivered['audience']).to eq({ 'utm' => { 'utm_source' => ['google'] }, 'visitor' => 'new' })
    expect(delivered['suppress']).to eq({ 'cookie_banner' => true, 'min_viewport_width' => 768 })
  end

  it 'carries the same schema message in pt_BR, the locale this installation serves' do
    inbox.widget_triggers = { 'triggers' => [{ 'id' => 'time_on_page', 'desktop' => { 'value' => -5 } }] }

    I18n.with_locale(:pt_BR) { inbox.valid? }

    expect(inbox.errors[:widget_triggers])
      .to eq(['tem valor inválido em "triggers/0/desktop/value": deve ser maior ou igual a 0'])
  end
end
