# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FunnelCustomField do
  let(:account) { create(:account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }

  describe 'validations' do
    it 'is valid with a well-formed key, label and type' do
      field = funnel.funnel_custom_fields.build(key: 'deal_value', label: 'Valor', field_type: 'number')
      expect(field).to be_valid
    end

    it 'rejects a key that does not start with a letter' do
      field = funnel.funnel_custom_fields.build(key: '1value', label: 'Valor', field_type: 'number')
      expect(field).not_to be_valid
      expect(field.errors[:key]).to be_present
    end

    it 'rejects an unknown field_type' do
      field = funnel.funnel_custom_fields.build(key: 'x', label: 'X', field_type: 'wormhole')
      expect(field).not_to be_valid
      expect(field.errors[:field_type]).to be_present
    end

    it 'enforces key uniqueness within a funnel' do
      funnel.funnel_custom_fields.create!(key: 'motivo', label: 'Motivo', field_type: 'text')
      dup = funnel.funnel_custom_fields.build(key: 'motivo', label: 'Outro', field_type: 'text')
      expect(dup).not_to be_valid
    end

    it 'allows the same key in different funnels' do
      other = Funnel.create!(account: account, name: 'Suporte')
      funnel.funnel_custom_fields.create!(key: 'motivo', label: 'Motivo', field_type: 'text')
      twin = other.funnel_custom_fields.build(key: 'motivo', label: 'Motivo', field_type: 'text')
      expect(twin).to be_valid
    end
  end

  describe '#attribute_key' do
    it 'namespaces the key by funnel id' do
      field = funnel.funnel_custom_fields.create!(key: 'valor', label: 'Valor', field_type: 'number')
      expect(field.attribute_key).to eq("funnel_#{funnel.id}_valor")
    end
  end

  describe 'scopes' do
    let!(:on_card_number) { funnel.funnel_custom_fields.create!(key: 'valor', label: 'Valor', field_type: 'number', show_on_card: true) }
    let!(:hidden_text) { funnel.funnel_custom_fields.create!(key: 'nota', label: 'Nota', field_type: 'text', show_on_card: false) }

    it 'numeric returns only number/rating fields' do
      expect(funnel.funnel_custom_fields.numeric).to contain_exactly(on_card_number)
    end

    it 'on_card returns only show_on_card fields' do
      expect(funnel.funnel_custom_fields.on_card).to contain_exactly(on_card_number)
    end
  end
end
