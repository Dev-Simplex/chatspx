/* global axios */
import ApiClient from '../ApiClient';

class GoogleClient extends ApiClient {
  constructor() {
    super('google', { accountScoped: true });
  }

  generateAuthorization(payload) {
    return axios.post(`${this.url}/authorization`, payload);
  }
}

export default new GoogleClient();
