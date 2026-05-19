/* global axios */
import ApiClient from '../ApiClient';

class CaptainDocument extends ApiClient {
  constructor() {
    super('captain/documents', { accountScoped: true });
  }

  get({ page = 1, searchKey, assistantId } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        searchKey,
        assistant_id: assistantId,
      },
    });
  }

  // Backend espera params.require(:document).permit(:name, :external_link, :assistant_id, :pdf_file)
  create({ name, externalLink, assistantId } = {}) {
    return axios.post(this.url, {
      document: {
        name,
        external_link: externalLink,
        assistant_id: assistantId,
      },
    });
  }
}

export default new CaptainDocument();
