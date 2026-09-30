require 'rails_helper'

RSpec.describe 'Catalog Public Images API' do
  let(:account) { create(:account) }

  describe 'GET /catalogo/fotos/:id' do
    it 'serve a capa do produto visível, sem sessão nem token' do
      produto = create(:catalog_product, :com_foto, account: account)

      get produto.public_image_url

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('image/png')
      expect(response.body).to eq(produto.capa.download)
    end

    it 'devolve 404 para produto oculto' do
      produto = create(:catalog_product, :com_foto, account: account)
      url = produto.public_image_url
      produto.update!(visible: false)

      get url

      expect(response).to have_http_status(:not_found)
    end

    it 'devolve 404 para produto sem imagem' do
      produto = create(:catalog_product, account: account)

      get catalog_public_image_path(id: produto.signed_id(purpose: CatalogProduct::IMAGEM_PUBLICA, expires_in: nil))

      expect(response).to have_http_status(:not_found)
    end

    it 'devolve 404 para identificador que não é o signed_id do produto' do
      get catalog_public_image_path(id: '1')

      expect(response).to have_http_status(:not_found)
    end
  end
end
