/* global axios */
import ApiClient from '../ApiClient';

/**
 * API do eval como produto (bloco 6.02).
 *
 * Duas coleções aninhadas no assistente: os CASOS (o que o cliente escreve) e as
 * EXECUÇÕES (o histórico do que rodou). A estimativa de custo é um GET próprio,
 * porque a tela precisa mostrar o número sem ter disparado nada.
 */
class CaptainEval extends ApiClient {
  constructor() {
    super('captain/assistants', { accountScoped: true });
  }

  casesUrl(assistantId) {
    return `${this.url}/${assistantId}/eval_cases`;
  }

  runsUrl(assistantId) {
    return `${this.url}/${assistantId}/eval_runs`;
  }

  getCases(assistantId) {
    return axios.get(this.casesUrl(assistantId));
  }

  createCase(assistantId, evalCase) {
    return axios.post(this.casesUrl(assistantId), { eval_case: evalCase });
  }

  updateCase(assistantId, id, evalCase) {
    return axios.patch(`${this.casesUrl(assistantId)}/${id}`, {
      eval_case: evalCase,
    });
  }

  deleteCase(assistantId, id) {
    return axios.delete(`${this.casesUrl(assistantId)}/${id}`);
  }

  getRuns(assistantId) {
    return axios.get(this.runsUrl(assistantId));
  }

  getRun(assistantId, id) {
    return axios.get(`${this.runsUrl(assistantId)}/${id}`);
  }

  /** O custo ANTES de rodar. Nada é disparado por esta chamada. */
  estimate(assistantId) {
    return axios.get(`${this.runsUrl(assistantId)}/estimate`);
  }

  run(assistantId) {
    return axios.post(this.runsUrl(assistantId));
  }

  compare(assistantId, baseId, comparadaId) {
    return axios.get(`${this.runsUrl(assistantId)}/compare`, {
      params: { base_id: baseId, comparada_id: comparadaId },
    });
  }
}

export default new CaptainEval();
