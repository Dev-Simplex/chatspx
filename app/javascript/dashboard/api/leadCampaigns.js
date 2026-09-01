/* global axios */
import ApiClient from './ApiClient';

// Campanhas de captação: volume por campanha no período, a configuração do hook que
// atende cada uma (template, agente, time, override) e a edição desse roteamento.
class LeadCampaigns extends ApiClient {
  constructor() {
    super('lead_campaigns', { accountScoped: true });
  }

  show(params = {}) {
    return axios.get(this.url, { params });
  }

  // O idioma do template não é digitado: viaja junto do template escolhido, porque a Meta
  // casa o par (nome, idioma) e o servidor recusa quando ele não confere.
  atualizarRoteamento(campaignId, roteamento) {
    return axios.put(this.url, { campaign_id: campaignId, roteamento });
  }
}

export default new LeadCampaigns();
