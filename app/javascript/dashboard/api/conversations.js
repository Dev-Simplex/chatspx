/* global axios */
import ApiClient from './ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getLabels(conversationID) {
    return axios.get(`${this.url}/${conversationID}/labels`);
  }

  updateLabels(conversationID, labels) {
    return axios.post(`${this.url}/${conversationID}/labels`, { labels });
  }

  getGhostSuggestion(conversationID) {
    return axios.post(`${this.url}/${conversationID}/ghost_suggestion`);
  }

  copilotChat(conversationID, messages) {
    return axios.post(`${this.url}/${conversationID}/copilot_chat`, {
      messages,
    });
  }

  copilotHistory(conversationID) {
    return axios.get(`${this.url}/${conversationID}/copilot_chat`);
  }

  clearCopilotHistory(conversationID) {
    return axios.delete(`${this.url}/${conversationID}/copilot_chat`);
  }
}

export default new ConversationApi();
