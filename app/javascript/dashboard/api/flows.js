/* global axios */
import ApiClient from './ApiClient';

class FlowsAPI extends ApiClient {
  constructor() {
    super('flows', { accountScoped: true });
  }

  execute(flowId, conversationIds) {
    return axios.post(`${this.url}/${flowId}/execute`, {
      conversation_ids: conversationIds,
    });
  }

  // Simulação (dry-run): retorna { steps, branch_path, conversation } — o caminho que o fluxo
  // seguiria, sem efetivar nada. conversationId é opcional (o backend pega uma conversa recente).
  simulate(flowId, conversationId = null) {
    return axios.post(`${this.url}/${flowId}/simulate`, {
      conversation_id: conversationId,
    });
  }

  // Painel "Execuções"/Logs: step-logs paginados do flow (mais recentes primeiro).
  getLogs(flowId, page = 1) {
    return axios.get(`${this.url}/${flowId}/logs`, { params: { page } });
  }
}

export default new FlowsAPI();
