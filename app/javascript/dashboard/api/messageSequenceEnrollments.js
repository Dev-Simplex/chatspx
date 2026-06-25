/* global axios */
import ApiClient from './ApiClient';

class MessageSequenceEnrollmentsAPI extends ApiClient {
  constructor() {
    super('message_sequence_enrollments', { accountScoped: true });
  }

  getForConversation(conversationId) {
    return axios.get(this.url, { params: { conversation_id: conversationId } });
  }

  enroll(messageSequenceId, conversationId) {
    return axios.post(this.url, {
      message_sequence_id: messageSequenceId,
      conversation_id: conversationId,
    });
  }
}

export default new MessageSequenceEnrollmentsAPI();
