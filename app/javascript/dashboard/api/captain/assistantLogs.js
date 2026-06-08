/* global axios */
import ApiClient from '../ApiClient';

class CaptainAssistantLogs extends ApiClient {
  constructor() {
    super('captain/assistant_logs', { accountScoped: true });
  }

  get({ page = 1, assistantId, eventType } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        assistant_id: assistantId,
        event_type: eventType,
      },
    });
  }
}

export default new CaptainAssistantLogs();
