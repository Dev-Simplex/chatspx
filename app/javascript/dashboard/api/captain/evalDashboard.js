/* global axios */
import ApiClient from '../ApiClient';

class CaptainEvalDashboard extends ApiClient {
  constructor() {
    super('captain/eval_dashboard', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }
}

export default new CaptainEvalDashboard();
