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

  contacts({ q, page = 1, since, until } = {}, options = {}) {
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
    return axios.get(`${this.url}/contacts`, config);
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

  messages(
    { q, page = 1, conversation_id = null, since, until, from, inboxId } = {},
    options = {}
  ) {
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
    const config = { params };
    if (options.signal) {
      config.signal = options.signal;
    }
    return axios.get(`${this.url}/messages`, config);
  }

  articles({ q, page = 1, since, until } = {}, options = {}) {
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
    return axios.get(`${this.url}/articles`, config);
  }
}

export default new SearchAPI();
