/* global axios */
import ApiClient from './ApiClient';

class ActiveAttendancesAPI extends ApiClient {
  constructor() {
    super('active_attendances', { accountScoped: true });
  }

  get({ page = 1, contactId, q } = {}) {
    const params = new URLSearchParams();
    params.set('page', String(page));
    if (contactId) {
      params.set('contact_id', String(contactId));
    }
    if (q) {
      params.set('q', q);
    }
    return axios.get(`${this.url}?${params.toString()}`);
  }
}

export default new ActiveAttendancesAPI();
