require 'rails_helper'

describe Catalog::MetaMessageBuilder do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before { account.update!(meta_catalog_id: 'cat-1') }

  def produto(atributos = {})
    create(:catalog_product, { account: account, meta_product_id: 'meta-1' }.merge(atributos))
  end

  describe '#perform' do
    it 'monta o payload de produto único no formato da Meta' do
      payload = described_class.new(conversation: conversation, produtos: produto(sku: 'ABC-1'), corpo: 'Olha esse').perform

      expect(payload).to eq(
        type: 'product',
        body: { text: 'Olha esse' },
        action: { catalog_id: 'cat-1', product_retailer_id: 'ABC-1' }
      )
    end

    it 'monta o payload multi-produto com sections por categoria' do
      categoria = create(:catalog_category, account: account, name: 'Bebidas')
      produtos = [produto(sku: 'ABC-1', category: categoria), produto(sku: 'ABC-2', category: categoria)]

      payload = described_class.new(conversation: conversation, produtos: produtos, corpo: 'Veja', cabecalho: 'Nossa vitrine').perform

      expect(payload[:type]).to eq('product_list')
      expect(payload[:header]).to eq(type: 'text', text: 'Nossa vitrine')
      expect(payload[:body]).to eq(text: 'Veja')
      expect(payload[:action][:catalog_id]).to eq('cat-1')
      expect(payload[:action][:sections]).to eq(
        [{ title: 'Bebidas', product_items: [{ product_retailer_id: 'ABC-1' }, { product_retailer_id: 'ABC-2' }] }]
      )
    end

    it 'levanta erro nomeado acima de 30 itens, em vez de truncar calado' do
      produtos = Array.new(31) { |i| produto(sku: "ABC-#{i}") }

      expect { described_class.new(conversation: conversation, produtos: produtos).perform }
        .to(raise_error { |erro| expect(erro.class.name).to eq('CustomExceptions::Catalog::TooManyProducts') })
    end

    it 'levanta erro nomeado para produto ainda não sincronizado' do
      expect { described_class.new(conversation: conversation, produtos: produto(meta_product_id: nil)).perform }
        .to(raise_error { |erro| expect(erro.class.name).to eq('CustomExceptions::Catalog::ProductNotSynced') })
    end

    it 'levanta erro nomeado para produto sem SKU' do
      expect { described_class.new(conversation: conversation, produtos: produto(sku: nil)).perform }
        .to(raise_error { |erro| expect(erro.class.name).to eq('CustomExceptions::Catalog::ProductNotSynced') })
    end

    it 'levanta erro nomeado quando a conta não tem catálogo na Meta' do
      account.update!(meta_catalog_id: nil)

      expect { described_class.new(conversation: conversation, produtos: produto(sku: 'ABC-1')).perform }
        .to(raise_error { |erro| expect(erro.class.name).to eq('CustomExceptions::Catalog::CatalogNotConfigured') })
    end

    it 'levanta erro nomeado quando a caixa não é whatsapp_cloud' do
      outra = create(:conversation, account: account, inbox: create(:inbox, account: account))

      expect { described_class.new(conversation: outra, produtos: produto(sku: 'ABC-1')).perform }
        .to(raise_error { |erro| expect(erro.class.name).to eq('CustomExceptions::Catalog::ChannelNotSupported') })
    end
  end
end
