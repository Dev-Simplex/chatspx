/* global axios */
import ApiClient from '../ApiClient';

class CaptainEvalDashboard extends ApiClient {
  constructor() {
    super('captain/eval_dashboard', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  episodes(params = {}) {
    return axios.get(`${this.url}/episodes`, { params });
  }

  conversationEpisodes(conversationDisplayId) {
    return axios.get(`${this.url}/conversation_episodes`, {
      params: { conversation_display_id: conversationDisplayId },
    });
  }

  annotate({ conversationDisplayId, episodeId, texto }) {
    return axios.post(`${this.url}/annotate`, {
      conversation_display_id: conversationDisplayId,
      episode_id: episodeId,
      texto,
    });
  }
}

export default new CaptainEvalDashboard();
