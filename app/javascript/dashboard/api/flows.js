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

  // Bloco 6.05 — o relatório do teste A/B de fluxo.
  //
  // A URL é de COLEÇÃO (`/flows/experiment`, não `/flows/:id/experiment`) porque um experimento
  // atravessa VÁRIAS variantes, que são vários flows: pendurá-lo num deles obrigaria a tela a
  // eleger "o dono" do experimento, pergunta que não tem resposta. O que identifica o relatório
  // é a `key`, e é ela que vai no query string.
  //
  // A JANELA É OPCIONAL, E A AUSÊNCIA DELA É UM RECURSO: sem `since`/`until` o servidor devolve
  // TODO o histórico (`FlowsController#experiment_period`), que é o que faz um experimento
  // encerrado mês passado continuar legível sem a tela adivinhar as datas. Por isso as chaves são
  // omitidas quando não vêm, em vez de irem vazias — mandar `since: ''` é pedir uma janela e
  // depender de o servidor tratar o branco.
  //
  // Devolve { experiment, variants[], comparisons[] }. `comparisons[].verdict` pode valer
  // `inconclusivo`: é a honestidade estatística do aceite, e a tela mostra o `reason` — não
  // esconde a linha.
  getExperiment(key, { since = null, until: ate = null } = {}) {
    return axios.get(`${this.url}/experiment`, {
      params: {
        key,
        ...(since ? { since } : {}),
        ...(ate ? { until: ate } : {}),
      },
    });
  }
}

export default new FlowsAPI();
