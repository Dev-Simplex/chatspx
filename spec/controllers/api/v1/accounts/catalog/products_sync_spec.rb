require 'rails_helper'

RSpec.describe 'Catálogo: sincronizar com a Meta', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:produto) { create(:catalog_product, :com_foto, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/catalog/products" }

  def configurar_espelho
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    account.update!(meta_catalog_id: '1234567890')
  end

  describe 'POST /catalog/products/sync' do
    it 'enfileira a passada da conta para o administrador' do
      configurar_espelho

      expect do
        post "#{base}/sync", headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Catalog::MetaSyncJob).with(account)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq('queued' => true)
    end

    it 'recusa o atendente' do
      configurar_espelho

      post "#{base}/sync", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'responde 422 quando a conta não tem espelho configurado' do
      expect do
        post "#{base}/sync", headers: admin.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Catalog::MetaSyncJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('catalog.meta_sync.not_configured', locale: account.locale))
    end
  end

  describe 'POST /catalog/products/:id/sync' do
    it 'devolve o produto a para_sincronizar e enfileira a passada da conta' do
      configurar_espelho
      produto.marcar_sincronizado!('meta-1')

      expect do
        post "#{base}/#{produto.id}/sync", headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Catalog::MetaSyncJob).with(account)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['meta_status']).to eq('pendente')
      expect(account.catalog_products.para_sincronizar).to include(produto)
    end

    it 'recusa o atendente' do
      configurar_espelho

      post "#{base}/#{produto.id}/sync", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /catalog/products' do
    it 'diz ao front se a conta tem espelho' do
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['meta']['meta_sync_enabled']).to be(false)

      configurar_espelho
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['meta']['meta_sync_enabled']).to be(true)
    end
  end
end
