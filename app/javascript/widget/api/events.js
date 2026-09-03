import { API } from 'widget/helpers/axios';
import { buildSearchParamsWithLocale } from '../helpers/urlParamsHelper';

export const generateEventParams = () => ({
  initiated_at: {
    timestamp: new Date().toString(),
  },
  referer: window.referrerURL || '',
});

export default {
  create(name) {
    const search = buildSearchParamsWithLocale(window.location.search);
    return API.post(`/api/v1/widget/events${search}`, {
      name,
      event_info: generateEventParams(),
    });
  },

  /**
   * Bloco 5.16 — o evento tipado do site do cliente.
   *
   * MESMO endpoint do `create`, de propósito: é a única porta por onde um fato do navegador
   * entra com a sessão do widget já autenticada. Uma segunda rota duplicaria autenticação,
   * throttle e a lista de nomes aceitos — e lista de nomes aceitos duplicada é o jeito
   * conhecido de um dos dois lados ficar permissivo sem ninguém perceber.
   *
   * `eventKey` é a chave de IDEMPOTÊNCIA, gerada uma vez por chamada de `track()` no host.
   * Ela vira `dedup_key` no servidor e colide no índice único `(account_id, name, dedup_key)`
   * do 5.03: reenvio da mesma chamada (falha de rede, retry do navegador) devolve o MESMO
   * `event_id` e não cria um segundo registro. Chamada nova traz chave nova e é fato novo.
   */
  track({ name, properties, eventKey }) {
    const search = buildSearchParamsWithLocale(window.location.search);
    return API.post(`/api/v1/widget/events${search}`, {
      name,
      properties: properties || {},
      event_key: eventKey,
    });
  },
};
