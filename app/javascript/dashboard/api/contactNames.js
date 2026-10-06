/* global axios */
import ApiClient from './ApiClient';

/** Número → nome salvo, em lote: GET /contact_names?phones[]=... (Contacts::SavedNames). */
class ContactNamesAPI extends ApiClient {
  constructor() {
    super('contact_names', { accountScoped: true });
  }

  get(phones) {
    return axios.get(this.url, { params: { phones } });
  }
}

export default new ContactNamesAPI();
