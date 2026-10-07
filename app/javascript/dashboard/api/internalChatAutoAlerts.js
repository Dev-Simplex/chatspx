/* global axios */
import ApiClient from './ApiClient';

// Avisos automáticos de uma sala de time (lead parado, meta batida).
class InternalChatAutoAlertsAPI extends ApiClient {
  constructor() {
    super('internal_channels', { accountScoped: true });
  }

  get(channelId) {
    return axios.get(`${this.url}/${channelId}/auto_alerts`);
  }

  update(channelId, events) {
    return axios.patch(`${this.url}/${channelId}/auto_alerts`, events);
  }
}

export default new InternalChatAutoAlertsAPI();
