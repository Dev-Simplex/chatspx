/* global axios */
import ApiClient from './ApiClient';

class ActiveAttendancesAPI extends ApiClient {
  constructor() {
    super('active_attendances', { accountScoped: true });
  }

  get({ page = 1, contactId } = {}) {
    const params = new URLSearchParams();
    params.set('page', String(page));
    if (contactId) {
      params.set('contact_id', String(contactId));
    }
    return axios.get(`${this.url}?${params.toString()}`);
  }
}

export default new ActiveAttendancesAPI();
