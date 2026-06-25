/* global axios */
import ApiClient from './ApiClient';

class InternalChatAPI extends ApiClient {
  constructor() {
    super('internal_channels', { accountScoped: true });
  }

  getChannels() {
    return axios.get(this.url);
  }

  createDm(userId) {
    return axios.post(this.url, { user_id: userId });
  }

  markRead(channelId) {
    return axios.post(`${this.url}/${channelId}/read`);
  }

  getMessages(channelId) {
    return axios.get(`${this.url}/${channelId}/internal_messages`);
  }

  sendMessage(channelId, content) {
    return axios.post(`${this.url}/${channelId}/internal_messages`, {
      content,
    });
  }

  getAgents() {
    return axios.get(`${this.baseUrl()}/agents_for_internal_chat`);
  }
}

export default new InternalChatAPI();
