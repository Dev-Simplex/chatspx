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

  // Analytics por nó (Fase 3.3): { period, total_entries, nodes: { node_id → { executions, failures,
  // pct } } } — as contagens pré-agregadas que viram as pills "142 · 38%" no canvas.
  getStats(flowId) {
    return axios.get(`${this.url}/${flowId}/stats`);
  }

  // Importa as Macros e AutomationRules legadas da conta como Flows equivalentes, rodando o
  // Flows::BackfillService no servidor (idempotente via trigger_config.backfill_source). Com
  // dry_run: true valida sem gravar. Retorna { dry_run, summary, flows }.
  importLegacy(dryRun = false) {
    return axios.post(`${this.url}/import`, { dry_run: dryRun });
  }
}

export default new FlowsAPI();
