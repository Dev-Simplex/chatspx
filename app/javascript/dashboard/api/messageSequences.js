/* global axios */
import ApiClient from './ApiClient';

class MessageSequencesAPI extends ApiClient {
  constructor() {
    super('message_sequences', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { message_sequence: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { message_sequence: data });
  }
}

export default new MessageSequencesAPI();
