/* global axios */
import ApiClient from './ApiClient';

class WahaConnections extends ApiClient {
  constructor() {
    super('waha_connections', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  get(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, data);
  }

  // `deleteInbox` decide se a CAIXA vai junto (e com ela conversas e mensagens, em cascata).
  // Vai como query string porque DELETE com corpo nao e lido de forma consistente por proxy e
  // por servidor. Omitido, o backend entende como NAO apagar.
  delete(id, { deleteInbox = false } = {}) {
    return axios.delete(`${this.url}/${id}`, {
      params: { delete_inbox: deleteInbox },
    });
  }

  getQRCode(id) {
    return axios.get(`${this.url}/${id}/qr_code`, {
      responseType: 'blob', // Sempre retorna imagem PNG como blob
    });
  }

  connect(id) {
    return axios.post(`${this.url}/${id}/connect`);
  }

  disconnect(id) {
    return axios.post(`${this.url}/${id}/disconnect`);
  }

  restart(id) {
    return axios.post(`${this.url}/${id}/restart`);
  }
}

export default new WahaConnections();
