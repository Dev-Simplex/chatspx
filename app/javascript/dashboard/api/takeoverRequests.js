/* global axios */
import ApiClient from './ApiClient';

class TakeoverRequestsAPI extends ApiClient {
  constructor() {
    super('takeover_requests', { accountScoped: true });
  }

  // Criar é sub-recurso da CONVERSA (herda authorize :show? do controller).
  create({ conversationId, reason }) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/takeover_requests`,
      { reason }
    );
  }

  approve(id, responseNote) {
    return axios.post(`${this.url}/${id}/approve`, {
      response_note: responseNote,
    });
  }

  deny(id, responseNote) {
    return axios.post(`${this.url}/${id}/deny`, {
      response_note: responseNote,
    });
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }

  get({ scope, status } = {}) {
    const params = new URLSearchParams();
    if (scope) params.set('scope', scope);
    if (status) params.set('status', status);
    const query = params.toString();
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }
}

export default new TakeoverRequestsAPI();
