import events from 'widget/api/events';
import { reportWidgetError } from 'widget/helpers/telemetry';

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
};

export default {
  namespaced: true,
  state: {},
  getters: {},
  actions,
  mutations: {},
};
