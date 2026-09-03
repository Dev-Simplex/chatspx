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

  it 'carries the same schema message in pt_BR, the locale this installation serves' do
    inbox.widget_triggers = { 'triggers' => [{ 'id' => 'time_on_page', 'desktop' => { 'value' => -5 } }] }

    I18n.with_locale(:pt_BR) { inbox.valid? }

    expect(inbox.errors[:widget_triggers])
      .to eq(['tem valor inválido em "triggers/0/desktop/value": deve ser maior ou igual a 0'])
  end
end
