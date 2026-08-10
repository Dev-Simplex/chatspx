/* global axios */
import ApiClient from './ApiClient';

class WahaConnections extends ApiClient {
  constructor() {
    super('waha_connections', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  // Saúde por inbox (liberada para agente): [{ inbox_id, inbox_name, status }]
  health() {
    return axios.get(`${this.url}/health`);
  }

  get(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, data);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
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
