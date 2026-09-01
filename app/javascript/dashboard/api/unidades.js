/* global axios */
import ApiClient from './ApiClient';

// Unidades físicas do cliente — contrato em docs/contratos/unidades.md.
// Leitura apenas nesta fase: a carga é pelo rake `spx:unidades:carregar`, porque endereço e
// telefone mudam uma vez por ano. O que muda toda semana é exceção, e ela tem API própria.
class UnidadesAPI extends ApiClient {
  constructor() {
    super('unidades', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }
}

export default new UnidadesAPI();
