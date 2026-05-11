/* global axios */

import ApiClient from '../ApiClient';

class OpenaiAPI extends ApiClient {
  constructor() {
    super('integrations/openai', { accountScoped: true });
  }

  testKey(apiKey) {
    return axios.post(`${this.url}/test_key`, { api_key: apiKey });
  }
}

export default new OpenaiAPI();
