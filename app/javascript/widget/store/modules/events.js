import events from 'widget/api/events';
import { reportWidgetError } from 'widget/helpers/telemetry';
import { emitTrackedEvent } from 'widget/helpers/sdkEventEmitter';

const actions = {
  create: async (_, { name }) => {
    try {
      await events.create(name);
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, { origem: 'store/events' });
    }
  },

  /**
   * Bloco 5.16 — `track()` do site: UMA chamada, os DOIS caminhos.
   *
   * A ORDEM É O PONTO. O registro server-side vem primeiro porque é dele que sai o `event_id`
   * (regra RC7, contrato §4.1): publicar no `dataLayer` antes e no servidor depois daria dois
   * ids diferentes para o mesmo fato, e a dedup do 5.13 não teria por onde juntar os dois lados.
   *
   * E POR ISSO A FALHA DE REDE NÃO CANCELA A PUBLICAÇÃO. Se o POST falha, o evento ainda vai ao
   * `dataLayer` — sem `event_id`, que é a verdade: nenhum id foi gerado. O contrário (silêncio no
   * navegador porque o servidor não respondeu) faria o GTM do cliente perder um evento que
   * aconteceu de verdade, por um motivo que não tem nada a ver com ele.
   */
  track: async (_, { name, properties = {} }) => {
    let eventId = null;

    try {
      const { data } = await events.track(name, properties);
      eventId = data?.event_id || null;
    } catch (error) {
      reportWidgetError(error, { origem: 'store/events/track' });

      // 422 é o servidor dizendo que a CHAMADA era inválida — nome fora do contrato, PII em
      // `properties`. Aí o silêncio é a resposta certa: publicar no `dataLayer` um payload que o
      // registro recusou colocaria no `window` do site exatamente o que a recusa existe para
      // manter fora dele. Qualquer outra falha é da rede, e o evento aconteceu de verdade.
      if (error?.response?.status === 422) return;
    }

    emitTrackedEvent(name, properties, eventId);
  },
};

export default {
  namespaced: true,
  state: {},
  getters: {},
  actions,
  mutations: {},
};
