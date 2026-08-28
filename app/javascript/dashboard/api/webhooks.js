/* global axios */
import ApiClient from './ApiClient';

/**
 * Bloco 4.14 — as tres rotas que faltavam ao lado do CRUD.
 *
 * Elas nao entram por `ApiClient` sozinhas porque nenhuma e um verbo REST do recurso: sao
 * acoes de MEMBRO (`/webhooks/:id/<acao>`). Os caminhos aqui sao cruzados com o roteador
 * do Rails por `spec/routing/front_urls_have_routes_spec.rb` — esta base ja escreveu um
 * caminho no plural contra uma rota no singular, e o 404 so apareceu em navegador real.
 */
class WebHooks extends ApiClient {
  constructor() {
    super('webhooks', { accountScoped: true });
  }

  /** O log de entregas: e ele que mostra a entrega falhada, com o motivo. */
  deliveries(id) {
    return axios.get(`${this.url}/${id}/deliveries`);
  }

  /**
   * O reenvio. `delivery_id` e a CHAVE PRIMARIA da linha, nao o `delivery_id` do cabecalho
   * — o controller faz `webhook_deliveries.find(params[:delivery_id])`. O identificador que
   * o destino usa para deduplicar e o mesmo da entrega original, e quem o preserva e o
   * servidor: o front nao o envia nem poderia.
   */
  replay(id, deliveryRecordId) {
    return axios.post(`${this.url}/${id}/replay`, {
      delivery_id: deliveryRecordId,
    });
  }

  /**
   * Rotacao. O segredo novo volta UMA vez, aqui — o `index` nao devolve segredo nenhum.
   * Quem chama e responsavel por NAO guardar esse valor no store: um registro do store com
   * segredo dentro e desenhado pela lista e pelo formulario de edicao, e foi assim que ele
   * vazava antes deste bloco.
   */
  rotateSecret(id) {
    return axios.post(`${this.url}/${id}/rotate_secret`);
  }
}

export default new WebHooks();
