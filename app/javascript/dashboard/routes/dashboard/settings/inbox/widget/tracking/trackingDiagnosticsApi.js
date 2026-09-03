/* global axios */
/**
 * O contrato REST do painel de diagnostico (bloco 5.14).
 *
 * Este arquivo existe separado do composable por um motivo pratico: ele e a
 * DECLARACAO do que a trilha de backend precisa expor, e serve de referencia
 * para quem for escrever o controller. Enquanto as rotas nao existirem, o
 * `GET` responde 404 e o painel diz isso na cara, com o caminho que falta —
 * um painel de auditoria vazio e silencioso e pior que nenhum painel, porque
 * o agente de suporte conclui "nao saiu evento" quando a verdade e "ninguem
 * consegue ver".
 *
 * As duas rotas, no escopo da conta e da inbox (a auditoria e POR INBOX, como
 * o kill switch e o pixel):
 *
 *   GET  /api/v1/accounts/:id/inboxes/:inbox_id/tracking_deliveries?limit=N
 *        -> { deliveries: [...], retention_days: 90, kill_switch: false }
 *
 *   POST /api/v1/accounts/:id/inboxes/:inbox_id/tracking_deliveries/test
 *        -> { delivery: {...} }   (T-C8.3 / T4.7: retorno visivel, status real)
 *
 * A forma de cada entrega e a das colunas de `tracking_deliveries`:
 * `event_id`, `name`, `destination`, `status`, `http_status`, `error_code`,
 * `error_message`, `emq`, `attempts`, `last_attempted_at`, `field_names`.
 * `field_names` e lista de NOMES — o modelo ja recusa outra coisa — e a tela
 * corta de novo em `trackingRedaction.js`.
 */

/**
 * O id da conta sai da URL, como em `ApiClient#accountIdFromRoute`.
 *
 * Repetir a leitura aqui em vez de instanciar um `ApiClient` e deliberado:
 * este modulo nao e um recurso REST completo (nao tem index/show/create/
 * update/delete) e herdar a classe inteira para usar dois caminhos seria
 * carregar um contrato que nao se cumpre.
 */
export const accountIdFromRoute = () => {
  const { pathname } = window.location;
  if (!pathname.includes('/app/accounts')) return '';

  return pathname.split('/')[3] ?? '';
};

const baseUrl = inboxId =>
  `/api/v1/accounts/${accountIdFromRoute()}/inboxes/${inboxId}/tracking_deliveries`;

/** O caminho que falta, para a tela poder NOMEAR o que nao existe ainda. */
export const diagnosticsPath = inboxId => baseUrl(inboxId);

export const fetchDeliveries = (inboxId, { limit = 25 } = {}) =>
  axios.get(baseUrl(inboxId), { params: { limit } });

export const sendTestEvent = inboxId => axios.post(`${baseUrl(inboxId)}/test`);
