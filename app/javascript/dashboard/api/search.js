/* global axios */
import ApiClient from './ApiClient';

class SearchAPI extends ApiClient {
  constructor() {
    super('search', { accountScoped: true });
  }

  get({ q }) {
    return axios.get(this.url, {
      params: {
        q,
      },
    });
  }

  contacts({ q, page = 1, since, until }) {
    return axios.get(`${this.url}/contacts`, {
      params: {
        q,
        page: page,
        since,
        until,
      },
    });
  }

  conversations({ q, page = 1, since, until } = {}, options = {}) {
    const config = {
      params: {
        q,
        page: page,
        since,
        until,
      },
    };
    if (options.signal) {
      config.signal = options.signal;
    }
    return axios.get(`${this.url}/conversations`, config);
  }

  messages({ q, page = 1, conversation_id = null, since, until, from, inboxId }) {
    const params = {
      q,
      page: page,
      since,
      until,
      from,
      inbox_id: inboxId,
    };
    if (conversation_id) {
      params.conversation_id = conversation_id;
    }
    return axios.get(`${this.url}/messages`, { params });
  }

  articles({ q, page = 1, since, until }) {
    return axios.get(`${this.url}/articles`, {
      params: {
        q,
        page: page,
        since,
        until,
      },
    });
  }
}

export default new SearchAPI();
