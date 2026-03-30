/* global axios */
import ApiClient from './ApiClient';

class ContactNotes extends ApiClient {
  constructor() {
    super('notes', { accountScoped: true });
  }

  contactUrl(contactId) {
    return `${this.baseUrl()}/contacts/${contactId}/notes`;
  }

  get(contactId) {
    return axios.get(this.contactUrl(contactId));
  }

  create(contactId, content) {
    return axios.post(this.contactUrl(contactId), { content });
  }

  delete(contactId, id) {
    return axios.delete(`${this.contactUrl(contactId)}/${id}`);
  }
}

export default new ContactNotes();
