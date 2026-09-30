require 'rails_helper'

describe Catalog::SendProductService do
  let(:account) { create(:account) }
  let(:usuario) { create(:user, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }

  def com_fotos(produto, quantidade)
    quantidade.times do |i|
      produto.images.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: "foto-#{i}.png", content_type: 'image/png')
    end
    produto
  end

  def enviar(*produtos)
    described_class.new(conversation: conversa, produtos: produtos, usuario: usuario).perform
  end

  def rodar_o_job
    allow_any_instance_of(Catalog::SendPhotosJob).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
    perform_enqueued_jobs(only: Catalog::SendPhotosJob)
  end

  context 'with WAHA inbox (sem catálogo)' do
    let(:inbox) { create(:channel_api, account: account).inbox.tap { |caixa| caixa.update!(waha_session_name: 'sessao-teste') } }

    it 'manda a capa com a legenda na hora e deixa as outras fotos para o job' do
      produto = com_fotos(create(:catalog_product, account: account, name: 'Casa no Centro'), 3)

      mensagem = enviar(produto)

      expect(mensagem.content).to include('*Casa no Centro*')
      expect(mensagem.attachments.size).to eq(1)
      expect(mensagem.content_attributes['catalog_products'].pluck('id')).to eq([produto.id])
      expect(Catalog::SendPhotosJob).to have_been_enqueued.once
    end

    it 'manda cada foto numa mensagem própria, sem legenda depois da primeira, e o menu no fim' do
      casa = com_fotos(create(:catalog_product, account: account, name: 'Casa'), 2)
      sala = com_fotos(create(:catalog_product, account: account, name: 'Sala'), 1)

      enviar(casa, sala)
      rodar_o_job

      mensagens = conversa.messages.outgoing.order(:id)
      expect(mensagens.map { |m| m.attachments.size }).to eq([1, 1, 1, 0])
      expect(mensagens.map { |m| m.content.to_s.lines.first&.strip }).to eq(['*Casa*', nil, '*Sala*', I18n.t('catalog.send.menu_header', count: 2)])
      expect(mensagens.last.content).to include('1. Casa', '2. Sala')
    end

    it 'respeita o teto de fotos por item' do
      produto = com_fotos(create(:catalog_product, account: account), CatalogProduct::FOTOS_NO_ENVIO + 2)

      enviar(produto)
      rodar_o_job

      expect(conversa.messages.outgoing.count).to eq(CatalogProduct::FOTOS_NO_ENVIO)
    end

    it 'manda só a legenda quando o item não tem foto' do
      mensagem = enviar(create(:catalog_product, account: account, name: 'Terreno'))

      expect(mensagem.content).to include('*Terreno*')
      expect(mensagem.attachments).to be_empty
      expect(Catalog::SendPhotosJob).not_to have_been_enqueued
    end
  end

  context 'with WhatsApp oficial inbox' do
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    end

    before { account.update!(meta_catalog_id: 'cat-1') }

    it 'manda a mensagem nativa de produto quando o item está espelhado na Meta' do
      produto = com_fotos(create(:catalog_product, account: account, sku: 'C-1', meta_product_id: 'meta-1'), 3)

      mensagem = enviar(produto)

      expect(mensagem.content_attributes['interactive_payload']).to include(
        'type' => 'product', 'action' => { 'catalog_id' => 'cat-1', 'product_retailer_id' => 'C-1' }
      )
      expect(mensagem.content_attributes['catalog_products'].pluck('id')).to eq([produto.id])
      expect(Catalog::SendPhotosJob).not_to have_been_enqueued
    end

    it 'manda lista de produtos, uma seção por categoria, com vários itens espelhados' do
      categoria = create(:catalog_category, account: account, name: 'Apartamentos')
      a = create(:catalog_product, account: account, sku: 'A-1', meta_product_id: 'm-1', category: categoria)
      b = create(:catalog_product, account: account, sku: 'B-1', meta_product_id: 'm-2')

      payload = enviar(a, b).content_attributes['interactive_payload']

      expect(payload['type']).to eq('product_list')
      expect(payload['action']['sections'].pluck('title')).to eq(['Apartamentos', I18n.t('catalog.message.section')])
    end

    it 'cai na foto com legenda quando algum item ainda não está espelhado' do
      espelhado = create(:catalog_product, account: account, meta_product_id: 'm-1')
      pendente = com_fotos(create(:catalog_product, account: account, name: 'Pendente'), 2)

      mensagem = enviar(pendente, espelhado)

      expect(mensagem.content_attributes).not_to have_key('interactive_payload')
      expect(mensagem.content).to include('*Pendente*')
      expect(mensagem.attachments.size).to eq(1)
    end

    it 'cai na foto com legenda quando a conta não tem catálogo na Meta' do
      account.update!(meta_catalog_id: nil)
      produto = create(:catalog_product, account: account, meta_product_id: 'm-1')

      expect(enviar(produto).content_attributes).not_to have_key('interactive_payload')
    end
  end
end
