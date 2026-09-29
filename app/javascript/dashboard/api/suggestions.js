/* global axios */
import ApiClient from './ApiClient';

class SuggestionsAPI extends ApiClient {
  constructor() {
    super('suggestions', { accountScoped: true });
  }

  // multipart: o anexo (foto ou vídeo) vai no mesmo POST do texto.
  create({ content, media }) {
    const formData = new FormData();
    formData.append('content', content);
    if (media) formData.append('media', media);

    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new SuggestionsAPI();
