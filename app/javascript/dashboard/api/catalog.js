/* global axios */
import ApiClient from './ApiClient';

// Catálogo de produtos. O CRUD mora em /catalog/products; mandar produto na conversa (C8) tem
// porta própria, porque lá o backend monta legenda, copia a foto e avisa o ERP. Não confundir com
// `/catalogo/produtos`, que é a porta do ERP (C3): outra autenticação, outro contrato.
class CatalogAPI extends ApiClient {
  constructor() {
    super('catalog/products', { accountScoped: true });
  }

  search({ q = '', page = 1 } = {}) {
    return axios.get(this.url, { params: { q, page, visible_only: true } });
  }

  // Filtrar é trabalho do servidor: a lista vem paginada de 25 em 25, então peneirar no cliente
  // esconderia o resto do catálogo em vez de filtrá-lo.
  listar({ page = 1, q = '', categoryId = '', visibleOnly = false } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        ...(q ? { q } : {}),
        ...(categoryId ? { category_id: categoryId } : {}),
        ...(visibleOnly ? { visible_only: true } : {}),
      },
    });
  }

  // Tirar UMA foto tem rota própria porque o update ACRESCENTA imagens em vez de substituir:
  // mandar a lista sem a foto removida não a apagaria, só deixaria tudo como estava.
  removerImagem(produtoId, imagemId) {
    return axios.delete(`${this.url}/${produtoId}/images/${imagemId}`);
  }

  sendToConversation(conversationId, productIds) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/catalog_products`,
      { product_ids: productIds }
    );
  }
}

const catalogAPI = new CatalogAPI();

export default catalogAPI;

// A tela de gestão importa pelo nome; é a mesma instância do default.
export const CatalogProducts = catalogAPI;

// Categorias são poucas, vêm sem paginação e a tela só as lê para montar o filtro: o ApiClient cru
// já resolve, sem uma subclasse que não acrescentaria nada.
export const CatalogCategories = new ApiClient('catalog/categories', {
  accountScoped: true,
});
