/* global axios */
import ApiClient from './ApiClient';

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  // Agregado read-only do disparo ancorado nesta campanha (por campaign_id).
  // Usa o axios GLOBAL (configurado com auth), igual ao ApiClient — nao o import.
  getStats(id) {
    return axios.get(`${this.url}/${id}/stats`);
  }

  // Carrega a lista (upload) de destinatarios — rows: [{ name, phone }].
  uploadRecipients(id, rows) {
    return axios.post(`${this.url}/${id}/recipients`, { rows });
  }

  // Inicia/retoma o disparo (dispatch_status: running).
  startDispatch(id) {
    return axios.post(`${this.url}/${id}/start`);
  }

  // Pausa o disparo mantendo os pendentes.
  pauseDispatch(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }
}

export default new CampaignsAPI();
