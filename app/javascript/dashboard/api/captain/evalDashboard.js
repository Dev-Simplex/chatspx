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
}

export default new CaptainEvalDashboard();
