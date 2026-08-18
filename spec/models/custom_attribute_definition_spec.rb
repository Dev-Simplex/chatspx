# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomAttributeDefinition do
  let(:account) { create(:account) }

  describe 'validations' do
    describe 'attribute_key format' do
      it 'allows alphanumeric keys with underscores' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'order_date_1')
        expect(cad).to be_valid
      end

      it 'allows hyphens and dots' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'order-date.v2')
        expect(cad).to be_valid
      end

      it 'allows Unicode letters' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: '客户类型')
        expect(cad).to be_valid
      end

      it 'rejects keys with single quotes' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: "x'||(SELECT 1)||'")
        expect(cad).not_to be_valid
        expect(cad.errors[:attribute_key]).to be_present
      end

      it 'rejects keys with spaces' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'order date')
        expect(cad).not_to be_valid
      end

      it 'rejects keys with semicolons' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'key; DROP TABLE users--')
        expect(cad).not_to be_valid
      end

      it 'rejects keys with parentheses' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'key()')
        expect(cad).not_to be_valid
      end

      it 'allows company custom attributes' do
        cad = build(:custom_attribute_definition, account: account, attribute_model: 'company_attribute')
        expect(cad).to be_valid
      end

      it 'rejects company custom attributes that conflict with standard company fields' do
        cad = build(:custom_attribute_definition, account: account, attribute_model: 'company_attribute', attribute_key: 'domain')
        expect(cad).not_to be_valid
        expect(cad.errors[:attribute_key]).to be_present
      end
    end
  end

  describe 'callbacks' do
    describe '#strip_attribute_key' do
      it 'strips leading and trailing whitespace from attribute_key' do
        cad = create(:custom_attribute_definition, account: account, attribute_key: '  order_date  ')
        expect(cad.attribute_key).to eq('order_date')
      end

      it 'strips leading and trailing whitespace from attribute_display_name' do
        cad = create(:custom_attribute_definition, account: account, attribute_display_name: '  Order Date  ')
        expect(cad.attribute_display_name).to eq('Order Date')
      end
    end

    describe 'filtered unread count invalidation' do
      let(:invalidator) { instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, custom_attribute_definition_changed!: true) }

      before do
        allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).with(account).and_return(invalidator)
        allow(Rails.configuration.dispatcher).to receive(:dispatch)
      end

      it 'invalidates conversation filters when a conversation custom attribute definition changes' do
        cad = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute')

        cad.update!(attribute_display_name: 'Updated Order Date')

        expect(invalidator).to have_received(:custom_attribute_definition_changed!).with(cad)
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
          'account.cache_invalidated',
          kind_of(Time),
          account: account,
          cache_keys: account.cache_keys
        )
      end

      it 'invalidates conversation filters when a conversation custom attribute definition is deleted' do
        cad = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute')

        cad.destroy!

        expect(invalidator).to have_received(:custom_attribute_definition_changed!).with(cad)
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
          'account.cache_invalidated',
          kind_of(Time),
          account: account,
          cache_keys: account.cache_keys
        )
      end

      it 'ignores contact custom attribute definition changes' do
        cad = create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute')

        cad.update!(attribute_display_name: 'Updated Contact Field')

        expect(invalidator).not_to have_received(:custom_attribute_definition_changed!)
        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      end
    end
  end

  # Selo de origem do painel (bloco 1.17). O flag distingue a definicao que o
  # CustomAttributes::AutoProvisionService criou sozinho, a partir de uma chave
  # que o site do cliente mandou, da que um agente cadastrou.
  describe '#auto_provisioned_from_website?' do
    let(:account) { create(:account) }

    def definition(description)
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                           attribute_key: "chave_#{SecureRandom.hex(4)}",
                                           attribute_description: description)
    end

    it 'e verdadeiro para a descricao que o servico grava em ingles' do
      expect(definition('Received from the website')).to be_auto_provisioned_from_website
    end

    it 'e verdadeiro para a descricao que o servico grava em pt-BR' do
      expect(definition('Recebido do site')).to be_auto_provisioned_from_website
    end

    it 'e falso para descricao escrita por um agente' do
      expect(definition('Valor do carrinho no checkout')).not_to be_auto_provisioned_from_website
    end

    it 'e falso quando nao ha descricao' do
      expect(definition(nil)).not_to be_auto_provisioned_from_website
      expect(definition('')).not_to be_auto_provisioned_from_website
    end

    it 'nasce verdadeiro quando o servico provisiona a chave vinda do site' do
      CustomAttributes::AutoProvisionService.new(
        account: account, attribute_model: :contact_attribute, custom_attributes: { 'carrinho_valor' => 4200 }
      ).perform

      expect(account.custom_attribute_definitions.find_by(attribute_key: 'carrinho_valor'))
        .to be_auto_provisioned_from_website
    end

    it 'para de valer se o agente reescrever a descricao — ele assumiu o atributo' do
      CustomAttributes::AutoProvisionService.new(
        account: account, attribute_model: :contact_attribute, custom_attributes: { 'carrinho_valor' => 4200 }
      ).perform
      found = account.custom_attribute_definitions.find_by(attribute_key: 'carrinho_valor')

      found.update!(attribute_description: 'Valor do carrinho, conferido pelo time')

      expect(found.reload).not_to be_auto_provisioned_from_website
    end
  end
end
