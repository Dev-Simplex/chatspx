/* global axios */
import ApiClient from './ApiClient';

class GalleryAPI extends ApiClient {
  constructor() {
    super('attachments', { accountScoped: true });
  }

  list({ types, inboxId, contactId, sort, before, after, q, page = 1 } = {}) {
    const params = {
      type: Array.isArray(types) ? types.join(',') : types,
      inbox_id: inboxId,
      contact_id: contactId,
      sort,
      before,
      after,
      q,
      page,
    };
    return axios.get(this.url, { params });
  }

  links({ inboxId, contactId, q, page = 1 } = {}) {
    const params = {
      inbox_id: inboxId,
      contact_id: contactId,
      q,
      page,
    };
    return axios.get(`${this.url}/links`, { params });
  }
}

export default new GalleryAPI();
