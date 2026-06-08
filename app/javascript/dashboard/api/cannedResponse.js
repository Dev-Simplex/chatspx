/* global axios */

import ApiClient from './ApiClient';

class CannedResponse extends ApiClient {
  constructor() {
    super('canned_responses', { accountScoped: true });
  }

  get({ searchKey }) {
    return axios.get(this.url, {
      params: searchKey ? { search: searchKey } : {},
    });
  }

  create(data) {
    return axios.post(this.url, this.buildPayload(data));
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, this.buildPayload(data));
  }

  // Com anexos -> multipart (FormData, axios seta o boundary). Sem anexos -> JSON
  // simples (o Rails wrap_parameters aninha sob :canned_response).
  // eslint-disable-next-line class-methods-use-this
  buildPayload(data) {
    const { attachments, ...rest } = data || {};
    if (!attachments || !attachments.length) return data;

    const form = new FormData();
    Object.keys(rest).forEach(key => {
      form.append(`canned_response[${key}]`, rest[key] ?? '');
    });
    attachments.forEach(file => {
      form.append('canned_response[attachments][]', file);
    });
    return form;
  }
}

export default new CannedResponse();
