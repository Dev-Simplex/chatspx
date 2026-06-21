/* global axios */
import ApiClient from './ApiClient';

class AttachmentBulkDownloadsAPI extends ApiClient {
  constructor() {
    super('attachment_bulk_downloads', { accountScoped: true });
  }

  // payload: { attachmentIds: [...] }  OU  { filters: {...}, conversationId }
  // filters em snake_case (type, inbox_id, contact_id, before, after, q).
  create({ attachmentIds, filters, conversationId } = {}) {
    return axios.post(this.url, {
      attachment_ids: attachmentIds,
      filters,
      conversation_id: conversationId,
    });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new AttachmentBulkDownloadsAPI();
