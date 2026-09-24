require 'rails_helper'

describe Catalog::MetaSyncService do
  let(:account) { create(:account) }
  let(:catalogo_id) { '1234567890' }
  let(:items_batch_url) { %r{graph\.facebook\.com/.+/#{catalogo_id}/items_batch} }
  let(:products_url) { %r{graph\.facebook\.com/.+/#{catalogo_id}/products} }

  before do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    account.update!(meta_catalog_id: catalogo_id)
  end

  def stub_espelho(itens)
    stub_request(:post, items_batch_url).to_return(status: 200, body: { handles: ['h1'] }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, products_url).to_return(status: 200, body: { data: itens }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    it 'manda o items_batch com retailer_id = SKU, preço e a foto pública, e carimba o produto' do
      produto = create(:catalog_product, :com_foto, account: account, sku: 'ABC-1', price_cents: 12_345, promo_price_cents: 9_900)
      stub_espelho([{ 'id' => 'meta-1', 'retailer_id' => 'ABC-1' }])

      described_class.new(account).perform

      expect(WebMock).to(have_requested(:post, items_batch_url).with do |req|
        corpo = JSON.parse(req.body)
        data = corpo['requests'].first['data']
        corpo['item_type'] == 'PRODUCT_ITEM' &&
          corpo['requests'].first['method'] == 'UPDATE' &&
          data['retailer_id'] == 'ABC-1' &&
          data['price'] == 12_345 &&
          data['sale_price'] == 9_900 &&
          data['currency'] == 'BRL' &&
          data['availability'] == 'in stock' &&
          data['image_url'] == produto.public_image_url
      end)

      produto.reload
      expect(produto.meta_product_id).to eq('meta-1')
      expect(produto.meta_synced_at).to be_present
      expect(account.catalog_products.para_sincronizar).to be_empty
    end

    it 'pula produto sem SKU sem derrubar o lote' do
      sem_sku = create(:catalog_product, :com_foto, account: account, sku: nil)
      com_sku = create(:catalog_product, :com_foto, account: account, sku: 'ABC-2')
      stub_espelho([{ 'id' => 'meta-2', 'retailer_id' => 'ABC-2' }])

      resultado = described_class.new(account).perform

      expect(resultado[:pulados]).to eq([{ id: sem_sku.id, motivo: :sem_sku }])
      expect(resultado[:enviados]).to eq(1)
      expect(com_sku.reload.meta_product_id).to eq('meta-2')
      expect(sem_sku.reload.meta_product_id).to be_nil
      expect(WebMock).to(have_requested(:post, items_batch_url).with { |req| JSON.parse(req.body)['requests'].size == 1 })
    end

    it 'pula produto sem foto sem derrubar o lote' do
      sem_foto = create(:catalog_product, account: account, sku: 'ABC-7')
      com_foto = create(:catalog_product, :com_foto, account: account, sku: 'ABC-8')
      stub_espelho([{ 'id' => 'meta-8', 'retailer_id' => 'ABC-8' }])

      resultado = described_class.new(account).perform

      expect(resultado[:pulados]).to eq([{ id: sem_foto.id, motivo: :sem_foto }])
      expect(resultado[:enviados]).to eq(1)
      expect(com_foto.reload.meta_product_id).to eq('meta-8')
      expect(sem_foto.reload.meta_product_id).to be_nil
      expect(WebMock).to(have_requested(:post, items_batch_url).with do |req|
        JSON.parse(req.body)['requests'].map { |r| r['data']['retailer_id'] } == ['ABC-8']
      end)
    end

    it 'tira do catálogo da Meta o produto que virou oculto' do
      produto = create(:catalog_product, :com_foto, account: account, sku: 'ABC-9')
      produto.marcar_sincronizado!('meta-9')
      produto.update!(visible: false)
      stub_espelho([])

      resultado = described_class.new(account).perform

      expect(resultado[:removidos]).to eq(1)
      expect(WebMock).to(have_requested(:post, items_batch_url).with do |req|
        JSON.parse(req.body)['requests'] == [{ 'method' => 'DELETE', 'data' => { 'retailer_id' => 'ABC-9' } }]
      end)

      produto.reload
      expect(produto.meta_product_id).to be_nil
      expect(produto.meta_synced_at).to be_nil
    end

    it 'não volta a mexer no produto oculto já tirado do espelho' do
      create(:catalog_product, :com_foto, account: account, sku: 'ABC-10', visible: false)
      stub_espelho([])

      resultado = described_class.new(account).perform

      expect(resultado[:removidos]).to eq(0)
      expect(WebMock).not_to have_requested(:post, items_batch_url)
    end

    it 'para a passada quando a Meta devolve 429, em vez de repetir' do
      create(:catalog_product, :com_foto, account: account, sku: 'ABC-3')
      stub_request(:post, items_batch_url).to_return(status: 429, body: { error: { message: 'rate limit' } }.to_json)

      resultado = described_class.new(account).perform

      expect(resultado[:limite_atingido]).to be(true)
      expect(WebMock).to have_requested(:post, items_batch_url).once
      expect(WebMock).not_to have_requested(:get, products_url)
    end

    it 'encerra em silêncio quando a conta não tem meta_catalog_id' do
      account.update!(meta_catalog_id: nil)
      create(:catalog_product, :com_foto, account: account, sku: 'ABC-4')

      resultado = described_class.new(account).perform

      expect(resultado[:enviados]).to eq(0)
      expect(WebMock).not_to have_requested(:post, items_batch_url)
    end

    it 'não carimba o produto que a Meta ainda não devolveu' do
      produto = create(:catalog_product, :com_foto, account: account, sku: 'ABC-5')
      stub_espelho([])

      described_class.new(account).perform

      expect(produto.reload.meta_product_id).to be_nil
    end

    it 'marca como esgotado o produto com estoque zerado' do
      create(:catalog_product, :com_foto, account: account, sku: 'ABC-6', stock: 0)
      stub_espelho([{ 'id' => 'meta-6', 'retailer_id' => 'ABC-6' }])

      described_class.new(account).perform

      expect(WebMock).to(have_requested(:post, items_batch_url)
        .with { |req| JSON.parse(req.body)['requests'].first['data']['availability'] == 'out of stock' })
    end
  end

  # O selo da aba (F3) tem que concordar com o que a passada faz com o produto.
  describe 'CatalogProduct#meta_status' do
    it 'é pendente antes da passada e sincronizado depois dela' do
      produto = create(:catalog_product, :com_foto, account: account, sku: 'ABC-8')
      expect(produto.meta_status).to eq('pendente')

      stub_espelho([{ 'id' => 'meta-8', 'retailer_id' => 'ABC-8' }])
      described_class.new(account).perform

      expect(produto.reload.meta_status).to eq('sincronizado')
    end

    it 'volta a pendente quando o produto muda depois da sincronização' do
      produto = create(:catalog_product, :com_foto, account: account, sku: 'ABC-9')
      produto.marcar_sincronizado!('meta-9')
      travel(1.minute) { produto.update!(name: 'Outro nome') }

      expect(produto.meta_status).to eq('pendente')
    end

    it 'é incompleto, com o que falta, quando a passada pularia o produto' do
      produto = create(:catalog_product, account: account, sku: nil)

      expect(produto.meta_status).to eq('incompleto')
      expect(produto.faltas_para_meta).to eq(%i[sku foto])
    end

    it 'não tem estado quando o produto está oculto' do
      expect(create(:catalog_product, :com_foto, account: account, visible: false).meta_status).to be_nil
    end
  end
end
