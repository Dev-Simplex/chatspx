/* global axios */
import ApiClient from './ApiClient';

class NpsReportsAPI extends ApiClient {
  constructor() {
    super('nps_responses', { accountScoped: true });
  }

  get({ page, from, to, user_ids, inbox_id, status, response_state, contact_id } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        since: from,
        until: to,
        sort: '-created_at',
        user_ids,
        inbox_id,
        status,
        response_state,
        contact_id,
      },
    });
  }

  getByConversation({ accountId, conversationId }) {
    return axios.get(`/api/v1/accounts/${accountId}/conversations/${conversationId}/nps_response`).catch(error => {
      if (error.response?.status === 404) {
        return { data: null };
      }
      throw error;
    });
  }

  getByContact({ accountId, contactId }) {
    return axios.get(`/api/v1/accounts/${accountId}/nps_responses`, {
      params: {
        contact_id: contactId,
        sort: '-answered_at',
        limit: 10,
      },
    });
  }

  sendSurvey({ accountId, conversationId }) {
    return axios.post(`/api/v1/accounts/${accountId}/conversations/${conversationId}/nps_responses/send`);
  }

  download({ from, to, user_ids, inbox_id, status } = {}) {
    return axios.get(`${this.url}/download`, {
      params: {
        since: from,
        until: to,
        sort: '-created_at',
        user_ids,
        inbox_id,
        status,
      },
    });
  }

  getMetrics({ from, to, user_ids, inbox_id, status } = {}) {
    return axios.get(`${this.url}/metrics`, {
      params: { since: from, until: to, user_ids, inbox_id, status },
    });
  }
}

export default new NpsReportsAPI();
