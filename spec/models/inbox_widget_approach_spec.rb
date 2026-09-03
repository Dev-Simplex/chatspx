require 'rails_helper'

# Bloco 3.20 (decisao D1) — a abordagem em tres niveis vira schema, dentro de `widget_triggers`
# (arbitragem A15: gatilho e QUANDO, nivel e COM QUE INTENSIDADE — mesmo objeto de decisao).
RSpec.describe Inbox, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  describe 'the three levels' do
    it 'persists approach: "bold"' do
      inbox.update!(widget_triggers: { 'approach' => 'bold' })

      expect(inbox.reload.widget_triggers['approach']).to eq('bold')
    end

    it 'accepts the three levels on desktop' do
      %w[discreet bold aggressive].each do |level|
        inbox.widget_triggers = { 'approach' => level }

        expect(inbox).to be_valid, "expected #{level} to be accepted"
      end
    end

    # A2 existe para produzir este erro: o valor gravado e ingles snake_case, o rotulo em pt-BR e i18n.
    it 'rejects approach: "agressivo" naming the field and listing the three levels' do
      inbox.widget_triggers = { 'approach' => 'agressivo' }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers])
        .to eq(['has an invalid value at "approach": value is not allowed (accepted: discreet, bold, aggressive)'])
    end

    it 'accepts degrade_on_return as a boolean and rejects anything else' do
      inbox.widget_triggers = { 'degrade_on_return' => false }
      expect(inbox).to be_valid

      inbox.widget_triggers = { 'degrade_on_return' => 'sim' }
      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers]).to eq(['has an invalid value at "degrade_on_return": must be of type boolean'])
    end
  end

  describe 'approach_mobile never inherits aggressive' do
    it 'accepts discreet and bold on mobile' do
      %w[discreet bold].each do |level|
        inbox.widget_triggers = { 'approach_mobile' => level }

        expect(inbox).to be_valid, "expected #{level} to be accepted on mobile"
      end
    end

    it 'rejects aggressive on mobile with a message that says WHY, not only that it is invalid' do
      inbox.widget_triggers = { 'approach_mobile' => 'aggressive' }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers]).to eq(
        ['has an invalid value at "approach_mobile": auto-open is not offered on mobile — the panel covers ' \
         'the whole screen there; use discreet or bold']
      )
    end

    it 'says the same thing in pt_BR, which is what the administrator reads' do
      inbox.widget_triggers = { 'approach_mobile' => 'aggressive' }

      I18n.with_locale(:pt_BR) { inbox.valid? }

      expect(inbox.errors[:widget_triggers]).to eq(
        ['tem valor inválido em "approach_mobile": abertura automática não é oferecida em celular — lá o painel ' \
         'cobre a tela inteira; use discreet ou bold']
      )
    end

    it 'still rejects garbage on mobile with the plain enum message' do
      inbox.widget_triggers = { 'approach_mobile' => 'agressivo' }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_triggers])
        .to eq(['has an invalid value at "approach_mobile": value is not allowed (accepted: discreet, bold)'])
    end
  end

  describe '#resolved_widget_approach — leitura derivada, sem migration e sem backfill (A4)' do
    it 'reads an inbox without the key as bold + degrade_on_return: true' do
      expect(inbox.widget_triggers).to be_nil
      expect(inbox.resolved_widget_approach).to eq(
        { 'approach' => 'bold', 'approach_mobile' => 'bold', 'degrade_on_return' => true }
      )
    end

    it 'keeps what is stored and defaults only what is missing' do
      inbox.widget_triggers = { 'approach' => 'aggressive' }

      expect(inbox.resolved_widget_approach).to eq(
        { 'approach' => 'aggressive', 'approach_mobile' => 'bold', 'degrade_on_return' => true }
      )
    end

    it 'never lets mobile inherit aggressive from the desktop level' do
      inbox.widget_triggers = { 'approach' => 'aggressive' }

      expect(inbox.resolved_widget_approach['approach_mobile']).to eq('bold')
    end

    it 'respects degrade_on_return: false' do
      inbox.widget_triggers = { 'degrade_on_return' => false }

      expect(inbox.resolved_widget_approach['degrade_on_return']).to be(false)
    end

    it 'does not write anything to the database when it resolves' do
      inbox.resolved_widget_approach

      expect(inbox.reload.additional_attributes).to eq({})
    end
  end
end
