/* global axios */
import ApiClient from './ApiClient';

/**
 * Configuração da distribuição DE UM TIME — o passo "Distribuição" da tela de edição.
 *
 * Não estende o client de `api/teams.js` de propósito: aquele arquivo é quente (outras
 * frentes mexem nele) e este recurso é aninhado sob o time, não um verbo a mais de time.
 *
 * Devolve a promise crua do axios: o `status` do erro importa aqui — 401 é "você não é
 * admin nem gerente deste time", e a tela precisa dizer isso em vez de "falhou".
 */
class TeamDistribuicao extends ApiClient {
  constructor() {
    super('teams', { accountScoped: true });
  }

  show(teamId) {
    return axios.get(`${this.url}/${teamId}/distribuicao`);
  }

  update(teamId, payload) {
    return axios.patch(`${this.url}/${teamId}/distribuicao`, payload);
  }
}

export default new TeamDistribuicao();
