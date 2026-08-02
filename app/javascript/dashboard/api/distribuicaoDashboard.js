/* global axios */
import ApiClient from './ApiClient';

class DistribuicaoDashboard extends ApiClient {
  constructor() {
    super('distribuicao_dashboard', { accountScoped: true });
  }

  show(params = {}) {
    return axios.get(this.url, { params });
  }

  // Drill-down "por que este lead foi pra este corretor": motivo, candidatos e a
  // política que valia na hora da decisão.
  designacoes(conversationId) {
    return axios.get(`${this.url}/designacoes`, {
      params: { conversation_id: conversationId },
    });
  }
}

export default new DistribuicaoDashboard();
