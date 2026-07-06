/* global axios */
import ApiClient from './ApiClient';

class FlowsAPI extends ApiClient {
  constructor() {
    super('flows', { accountScoped: true });
  }

  execute(flowId, conversationIds) {
    return axios.post(`${this.url}/${flowId}/execute`, {
      conversation_ids: conversationIds,
    });
  }
}

export default new FlowsAPI();
