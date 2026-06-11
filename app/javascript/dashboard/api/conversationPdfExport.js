/* global axios */
import ApiClient from './ApiClient';

class ConversationPdfExportApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true, apiVersion: 'v2' });
  }

  create(conversationId, filters) {
    return axios.post(`${this.url}/${conversationId}/pdf_exports`, {
      pdf_export: filters,
    });
  }

  show(conversationId, exportId) {
    return axios.get(`${this.url}/${conversationId}/pdf_exports/${exportId}`);
  }
}

export default new ConversationPdfExportApi();
