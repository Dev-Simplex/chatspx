/* global axios */
import ApiClient from './ApiClient';

// Catálogo do painel (C2). Não confundir com `/catalogo/produtos`, que é a porta do ERP (C3):
// outra autenticação, outro contrato.
class CatalogProductsAPI extends ApiClient {
  constructor() {
    super('catalog/products', { accountScoped: true });
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
}

export const CatalogProducts = new CatalogProductsAPI();

// Categorias são poucas, vêm sem paginação e a tela só as lê para montar o filtro: o ApiClient cru
// já resolve, sem uma subclasse que não acrescentaria nada.
export const CatalogCategories = new ApiClient('catalog/categories', {
  accountScoped: true,
});
