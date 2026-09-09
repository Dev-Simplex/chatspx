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

  // A linha do tempo dos leads que caíram no consultor pelo rodízio: quanto a IA cobriu, quanto
  // o lead esperou ele pegar, e quanto durou o atendimento.
  linhaDoTempo(userId, params = {}) {
    return axios.get(`${this.url}/linha_do_tempo`, {
      params: { ...params, user_id: userId },
    });
  }
}

export default new DistribuicaoDashboard();
