require 'rails_helper'

# Lacuna da §B.4 do plano 22, roteada pelo coordenador em 18/08/2026: o perfil `marketing` exige
# "2 a 4 opcoes de intencao nomeadas" na tela inicial, e nao havia campo declarado em lugar nenhum.
# Contrato: `widget_appearance.home_intents` — array de {id, label}, 2 a 4 quando presente.
RSpec.describe Inbox, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def with_intents(intents)
    inbox.widget_appearance = { 'home_intents' => intents }
    inbox
  end

  it 'accepts two named intents' do
    with_intents([{ 'id' => 'pricing', 'label' => 'Quero um orçamento' },
                  { 'id' => 'support', 'label' => 'Preciso de ajuda' }])

    expect(inbox).to be_valid
  end

  it 'accepts four and refuses five, naming the field and the limit' do
    four = Array.new(4) { |i| { 'id' => "intent_#{i}", 'label' => "Opção #{i}" } }
    expect(with_intents(four)).to be_valid

    inbox.errors.clear
    with_intents(four + [{ 'id' => 'intent_5', 'label' => 'Demais' }])

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance])
      .to eq(['has an invalid value at "home_intents": is over the limit of 4 items'])
  end

  it 'accepts an empty list — the home screen of today, with no named options' do
    expect(with_intents([])).to be_valid
  end

  it 'refuses a single option, because one option is not a choice' do
    with_intents([{ 'id' => 'pricing', 'label' => 'Quero um orçamento' }])

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance])
      .to eq(['needs 2 to 4 intent options, or none — a single option is not a choice'])
  end

  it 'refuses two options sharing the same id' do
    with_intents([{ 'id' => 'pricing', 'label' => 'Orçamento' },
                  { 'id' => 'pricing', 'label' => 'Preço' }])

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance]).to eq(['has intent options sharing the same id: pricing'])
  end

  it 'refuses an id that is not snake_case, naming the field' do
    with_intents([{ 'id' => 'Quero Orçamento', 'label' => 'Orçamento' },
                  { 'id' => 'support', 'label' => 'Ajuda' }])

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance].first).to start_with('has an invalid value at "home_intents/0/id"')
  end

  it 'refuses an option without a label and one with an empty label' do
    with_intents([{ 'id' => 'pricing' }, { 'id' => 'support', 'label' => 'Ajuda' }])
    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance]).to eq(['has an invalid value at "home_intents/0": missing required field: label'])

    inbox.errors.clear
    with_intents([{ 'id' => 'pricing', 'label' => '' }, { 'id' => 'support', 'label' => 'Ajuda' }])
    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance])
      .to eq(['has an invalid value at "home_intents/0/label": needs at least 1 character'])
  end

  it 'refuses a label over 48 characters, which stops being a named option and becomes a sentence' do
    with_intents([{ 'id' => 'pricing', 'label' => 'a' * 49 }, { 'id' => 'support', 'label' => 'Ajuda' }])

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance])
      .to eq(['has an invalid value at "home_intents/0/label": is over the limit of 48 characters'])
  end

  it 'refuses an unknown field inside an option' do
    with_intents([{ 'id' => 'pricing', 'label' => 'Orçamento', 'action' => 'open_flow' },
                  { 'id' => 'support', 'label' => 'Ajuda' }])

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance])
      .to eq(['has an invalid value at "home_intents/0/action": unknown field'])
  end

  describe 'what happens when the key is absent' do
    it 'resolves to an empty list, so an existing inbox behaves exactly as it does today' do
      expect(inbox.widget_appearance).to be_nil
      expect(inbox.resolved_widget_appearance['home_intents']).to eq([])
    end

    it 'keeps the stored list when there is one' do
      intents = [{ 'id' => 'pricing', 'label' => 'Orçamento' }, { 'id' => 'support', 'label' => 'Ajuda' }]
      inbox.update!(widget_appearance: { 'home_intents' => intents })

      expect(inbox.reload.resolved_widget_appearance['home_intents']).to eq(intents)
    end
  end
end
