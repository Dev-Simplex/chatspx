require 'rails_helper'

# Bloco 3.18 — a aparencia sai do localStorage do admin e vira configuracao com schema.
RSpec.describe Inbox, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  let(:full_appearance) do
    {
      'theme' => 'dark', 'position' => 'left', 'offset_x' => 24, 'offset_y' => 16,
      'launcher_type' => 'expanded_bubble', 'launcher_text' => 'Fale com a gente',
      'hide_bubble' => false, 'panel_style' => 'flat', 'launcher_icon' => 'agent_photo'
    }
  end

  it 'persists a full valid appearance object untouched' do
    inbox.update!(widget_appearance: full_appearance)

    expect(inbox.reload.widget_appearance).to eq(full_appearance)
  end

  it 'rejects position: "center" naming the field and listing what is accepted' do
    inbox.widget_appearance = { 'position' => 'center' }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance])
      .to eq(['has an invalid value at "position": value is not allowed (accepted: left, right)'])
  end

  it 'rejects an offset of 500 naming the field and the limit' do
    inbox.widget_appearance = { 'offset_x' => 500 }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance])
      .to eq(['has an invalid value at "offset_x": must be less than or equal to 200'])
  end

  it 'rejects a launcher text of 200 characters naming the field and the limit' do
    inbox.widget_appearance = { 'launcher_text' => 'a' * 200 }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance])
      .to eq(['has an invalid value at "launcher_text": is over the limit of 64 characters'])
  end

  it 'accepts a launcher text exactly at the limit' do
    inbox.widget_appearance = { 'launcher_text' => 'a' * 64 }

    expect(inbox).to be_valid
  end

  it 'rejects an unknown appearance field' do
    inbox.widget_appearance = { 'positon' => 'left' }

    expect(inbox).not_to be_valid
    expect(inbox.errors[:widget_appearance]).to eq(['has an invalid value at "positon": unknown field'])
  end

  describe 'the jsonb size ceiling' do
    # `additional_attributes` inteiro vai para o HTML de TODA pagina do site do cliente
    # (`show.html.erb`) e e servido a qualquer agente com a inbox atribuida (`_inbox.json.jbuilder:27`).
    # Medicao desta VM em 18/08/2026: 17 inboxes, o maior `additional_attributes` tem 56 bytes.
    # O teto de 16.384 e ~292x o maior valor real — folga para crescer, teto para nao virar payload.
    it 'accepts an object comfortably under the ceiling' do
      inbox.widget_appearance = { 'launcher_text' => 'a' * 64 }

      expect(inbox).to be_valid
      expect(inbox.additional_attributes.to_json.bytesize).to be < Inbox::MAX_ADDITIONAL_ATTRIBUTES_BYTES
    end

    it 'rejects an object over the ceiling naming the limit' do
      inbox.widget_tracking = { 'event_map' => Array.new(400) { |i| ["event_#{i}", 'a' * 40] }.to_h }

      expect(inbox.additional_attributes.to_json.bytesize).to be > Inbox::MAX_ADDITIONAL_ATTRIBUTES_BYTES
      expect(inbox).not_to be_valid
      expect(inbox.errors[:additional_attributes])
        .to eq(['is over the limit of 16384 bytes — it is served on every page of the customer site'])
    end

    it 'says the same thing in pt_BR' do
      inbox.widget_tracking = { 'event_map' => Array.new(400) { |i| ["event_#{i}", 'a' * 40] }.to_h }

      I18n.with_locale(:pt_BR) { inbox.valid? }

      expect(inbox.errors[:additional_attributes])
        .to eq(['passa do limite de 16384 bytes — ele é servido em toda página do site do cliente'])
    end
  end

  describe '#resolved_widget_appearance' do
    it 'fills every field with the factory default when nothing is stored' do
      expect(inbox.resolved_widget_appearance).to eq(WidgetAppearanceSchema::DEFAULTS)
    end

    it 'keeps the stored value and defaults only what is missing' do
      inbox.widget_appearance = { 'position' => 'left' }

      resolved = inbox.resolved_widget_appearance

      expect(resolved['position']).to eq('left')
      expect(resolved['launcher_icon']).to eq('default')
      expect(resolved['theme']).to eq('light')
      expect(resolved.keys).to match_array(WidgetAppearanceSchema::DEFAULTS.keys)
    end

    it 'ignores a stored key that is not part of the schema' do
      inbox.additional_attributes = { 'widget_appearance' => { 'position' => 'left', 'legacy' => 'x' } }

      expect(inbox.resolved_widget_appearance).not_to have_key('legacy')
    end
  end
end
