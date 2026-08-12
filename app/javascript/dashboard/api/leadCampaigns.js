/* global axios */
import ApiClient from './ApiClient';

// Viewer só-leitura das campanhas de captação: volume por campanha no período e a
// configuração do hook que atende cada uma (template, agente, time, override).
class LeadCampaigns extends ApiClient {
  constructor() {
    super('lead_campaigns', { accountScoped: true });
  }

  show(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new LeadCampaigns();
