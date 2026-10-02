/* global axios */

import ApiClient from '../ApiClient';

// Painel do Captador: fala só com o próprio ChatSPX, que repassa ao Captador assinado
// (Api::V1::Accounts::Integrations::CaptadorController). Sem CORS nem cookie de terceiro.
class CaptadorAPI extends ApiClient {
  constructor() {
    super('integrations/captador', { accountScoped: true });
  }

  getLead(conversationId) {
    return axios.get(`${this.url}/lead`, {
      params: { conversation_id: conversationId },
    });
  }

  moveStage(conversationId, etapaId) {
    return axios.post(`${this.url}/mover`, {
      conversation_id: conversationId,
      etapa_id: etapaId,
    });
  }
}

export default new CaptadorAPI();
