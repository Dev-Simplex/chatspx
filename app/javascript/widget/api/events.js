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
   * Bloco 5.16 — o evento próprio do site (`window.$chatwoot.track()`).
   *
   * MESMO ENDPOINT, e a economia não é de código: é de contrato. O servidor distingue os dois
   * vocabulários pelo prefixo `chatspx_` e só o de tracking vira registro — evento de barramento
   * continua indo ao dispatcher. Uma rota nova exigiria repetir aqui a autenticação por
   * `website_token`, o `X-Auth-Token` e a busca do `contact_inbox`, três coisas que já estão
   * resolvidas neste caminho.
   *
   * `event_info` leva as propriedades CRUAS do integrador, sem os campos de diagnóstico que
   * `generateEventParams()` acrescenta: elas viram `properties` do evento, que viaja para o
   * `dataLayer` e para os params do `fbq`/`gtag`.
   */
  track(name, properties = {}) {
    const search = buildSearchParamsWithLocale(window.location.search);
    return API.post(`/api/v1/widget/events${search}`, {
      name,
      event_info: properties,
    });
  },
};
