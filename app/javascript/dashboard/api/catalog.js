/* global axios */
import ApiClient from './ApiClient';

// Catálogo de produtos (C8). O CRUD mora em /catalog/products; mandar produto na conversa tem
// porta própria, porque lá o backend monta legenda, copia a foto e avisa o ERP.
class CatalogAPI extends ApiClient {
  constructor() {
    super('catalog/products', { accountScoped: true });
  }

  search({ q = '', page = 1 } = {}) {
    return axios.get(this.url, { params: { q, page, visible_only: true } });
  }

  sendToConversation(conversationId, productIds) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/catalog_products`,
      { product_ids: productIds }
    );
  }
}

export default new CatalogAPI();
