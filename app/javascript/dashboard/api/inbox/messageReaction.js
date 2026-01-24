/* global axios */
import ApiClient from '../ApiClient';

class MessageReactionApi extends ApiClient {
  constructor() {
    super('', { accountScoped: false });
  }

  create({ accountId, conversationId, messageId, emoji }) {
    return axios.post(
      `/api/v1/accounts/${accountId}/conversations/${conversationId}/messages/${messageId}/reactions`,
      {
        reaction: { emoji },
      }
    );
  }

  delete({ accountId, conversationId, messageId, reactionId }) {
    return axios.delete(
      `/api/v1/accounts/${accountId}/conversations/${conversationId}/messages/${messageId}/reactions/${reactionId}`
    );
  }
}

export default new MessageReactionApi();



