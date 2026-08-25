/* global axios */
import ApiClient from './ApiClient';

class DistribuicaoPolicies extends ApiClient {
  constructor() {
    super('distribuicao_policies', { accountScoped: true });
  }

  // A chave do recurso é o TIME, não o id da política: quem abre a tela escolhe
  // um time e o backend cria ou atualiza a política daquele time no mesmo PUT.
  // Por isso `update` (PATCH /:id) do ApiClient não serve aqui.
  upsert(teamId, policy) {
    return axios.put(`${this.url}/${teamId}`, { policy });
  }
}

export default new DistribuicaoPolicies();
