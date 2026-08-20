/* global axios */
import ApiClient from '../ApiClient';

class CaptainResponses extends ApiClient {
  constructor() {
    super('captain/assistant_responses', { accountScoped: true });
  }

  get({ page = 1, search, assistantId, documentId, signal } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        search,
        assistant_id: assistantId,
        document_id: documentId,
      },
      signal,
    });
  }

  // Backend espera params.require(:assistant_response).permit(:question, :answer, :assistant_id, :status)
  create({ question, answer, assistantId, status = 'approved' } = {}) {
    return axios.post(this.url, {
      assistant_response: {
        question,
        answer,
        assistant_id: assistantId,
        status,
      },
    });
  }

  // O update do ApiClient base manda o objeto cru; o backend exige o wrapper
  // assistant_response (params.require), entao sobrescrevemos.
  update(id, { question, answer, status } = {}) {
    return axios.patch(`${this.url}/${id}`, {
      assistant_response: {
        question,
        answer,
        status,
      },
    });
  }
}

export default new CaptainResponses();
