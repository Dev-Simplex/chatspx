/* global axios */
import ApiClient from './ApiClient';

// Exceções datadas de funcionamento — a camada que muda toda semana.
// Sem `update` de propósito: corrigir uma exceção é apagá-la e criar outra.
class UnidadeExcecoesAPI extends ApiClient {
  constructor() {
    super('unidade_excecoes', { accountScoped: true });
  }

  // Só devolve as que ainda não venceram — a vencida morre sozinha, é o ponto do desenho.
  getAll() {
    return axios.get(this.url);
  }

  create(unidadeExcecao) {
    return axios.post(this.url, { unidade_excecao: unidadeExcecao });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new UnidadeExcecoesAPI();
