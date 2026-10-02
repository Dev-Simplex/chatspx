# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Catalog::ProductMessageBuilder do
  let(:account) { create(:account) }
  let(:produto) do
    create(:catalog_product, account: account, name: 'Casa no Centro', sku: 'C-10', description: 'Perto de tudo',
                             price_cents: 45_000_000, custom_attributes: { 'dormitorios' => 3, 'captador' => 'João' })
  end

  before do
    create(:custom_attribute_definition, account: account, attribute_model: 'catalog_attribute', attribute_key: 'dormitorios',
                                         attribute_display_name: 'Dormitórios', attribute_display_type: 'number')
    create(:custom_attribute_definition, account: account, attribute_model: 'catalog_attribute', attribute_key: 'captador',
                                         attribute_display_name: 'Captador', attribute_display_type: 'text', hidden: true)
  end

  describe '#legenda' do
    it 'sai na ordem nome, preço, campos, descrição e código, sem o campo interno' do
      expect(described_class.new(produto).legenda).to eq(
        "*Casa no Centro*\nR$ 450.000,00\nDormitórios: 3\nPerto de tudo\nCód. C-10"
      )
    end

    it 'mostra o preço cheio riscado quando há promoção' do
      produto.update!(promo_price_cents: 40_000_000)

      expect(described_class.new(produto).legenda).to include("~R$ 450.000,00~ R$ 400.000,00\n")
    end

    it 'não tem linha de preço quando o item não tem preço' do
      produto.update!(price_cents: nil)

      expect(described_class.new(produto).legenda).to eq("*Casa no Centro*\nDormitórios: 3\nPerto de tudo\nCód. C-10")
    end

    it 'não mostra o código quando a conta esconde o SKU' do
      account.update!(catalog_hidden_fields: ['sku'])

      expect(described_class.new(produto).legenda).not_to include('Cód.')
    end
  end

  describe '#content_attributes' do
    it 'grava na cópia da mensagem os campos não internos, já formatados' do
      retrato = described_class.new(produto).content_attributes[:catalog_products].first

      expect(retrato['custom_fields']).to eq([{ 'label' => 'Dormitórios', 'value' => '3' }])
    end

    it 'aceita item sem preço' do
      produto.update!(price_cents: nil)
      retrato = described_class.new(produto).content_attributes[:catalog_products].first

      expect(retrato).to include('price_cents' => nil, 'current_price_cents' => nil)
    end
  end

  describe '#itens_do_menu' do
    it 'lista só o nome quando o item não tem preço' do
      produto.update!(price_cents: nil)

      expect(described_class.new(produto).itens_do_menu).to eq([{ 'title' => '1. Casa no Centro' }])
    end
  end
end
