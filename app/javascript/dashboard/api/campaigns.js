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
}

export default new CampaignsAPI();
