/* global axios */
import ApiClient from './ApiClient';

// CHAT-177: metas mensais e ranking do time.
class PerformanceGoalsAPI extends ApiClient {
  constructor() {
    super('performance_goals', { accountScoped: true });
  }

  getGoals(month) {
    return axios.get(this.url, { params: { month } });
  }

  saveGoals({ month, goals }) {
    return axios.put(this.url, { month, goals });
  }

  updateVisibility(visibility) {
    return axios.patch(`${this.url}/visibility`, { visibility });
  }

  getRanking({ month, scope, teamId }) {
    return axios.get(this.url.replace(/performance_goals$/, 'performance_ranking'), {
      params: { month, scope, team_id: teamId || undefined },
    });
  }
}

export default new PerformanceGoalsAPI();
