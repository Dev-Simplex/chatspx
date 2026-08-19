import events from 'widget/api/events';
import { reportWidgetError } from 'widget/helpers/telemetry';
import { IFrameHelper } from 'widget/helpers/utils';

/**
 * Blocos 5.05 e 5.16 — o `event_id` volta do servidor e ATRAVESSA para o host.
 *
 * O `event_id` nasce no backend (regra RC7: um id por ação do usuário, gerado onde há
 * autoridade) e precisa chegar à ponte de tags, que vive no `window` do site do cliente. Ele
 * é o mesmo id que o caminho server-side de 5.11 mandará ao CAPI: é por ele que a Meta
 * reconhece os dois envios como UM fato dentro da janela de 48 h. Sem a travessia, o cliente
 * vê a mesma conversão contada duas vezes.
 *
 * Não é `emitSdkEvent`: aquele é o vocabulário `chatwoot:*`, que vai ao `window` do site e é
 * legível por qualquer script de terceiro da página. Este aqui é interno — vai do iframe para
 * o SDK e para na ponte de tags, que decide o disparo.
 */
const encaminharAoHost = data => {
  const nome = data?.name;
  if (!nome) return;

  IFrameHelper.sendMessage({
    event: 'trackingEvent',
    name: nome,
    properties: data.properties || {},
    eventId: data.event_id || null,
  });
};

const actions = {
  create: async (_, { name }) => {
    try {
      const { data } = await events.create(name);
      // `data.name` vem nulo quando o fato não tem contraparte no vocabulário `chatspx_` —
      // é o caso declarado de `campaign.triggered` (contrato §2). Ausência declarada, e
      // `encaminharAoHost` a lê como "não há evento de tracking aqui".
      encaminharAoHost(data);
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, { origem: 'store/events' });
    }
  },

  /**
   * Bloco 5.16 — `track(name, properties)`.
   *
   * As `properties` que o site mandou seguem para o host junto com o `event_id`, porque é o
   * host que publica no `dataLayer` — o aceite do bloco é "chega ao registro server-side E ao
   * `dataLayer` pela mesma chamada". Um 422 (nome fora do formato, PII crua) não vira exceção
   * no site do cliente: vira erro CONTADO, como todo o resto deste módulo.
   */
  track: async (_, { name, properties, eventKey }) => {
    try {
      const { data } = await events.track({ name, properties, eventKey });
      encaminharAoHost({ ...data, properties });
    } catch (error) {
      reportWidgetError(error, { origem: 'store/events#track' });
    }
  },
};

export default {
  namespaced: true,
  state: {},
  getters: {},
  actions,
  mutations: {},
};
